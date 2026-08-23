//
//  fetchkcache.swift
//  lara
//
//  Created by ruter on 12.05.26.
//

import Foundation

func syskcpath() -> String? {
    guard let hash = getbmhash() else { return nil }
    return "/private/preboot/\(hash)/System/Library/Caches/com.apple.kernelcaches/kernelcache"
}

func larakcpath() -> String? {
    guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
    return docs.appendingPathComponent("kernelcache").path
}

func fetchkcache() -> Bool {
    guard ds_is_ready(),
          ds_get_our_proc() != 0,
          ds_get_our_task() != 0,
          off_proc_p_fd != 0,
          off_filedesc_fd_ofiles != 0,
          off_fileproc_fp_glob != 0,
          off_fileglob_fg_data != 0,
          off_vnode_v_data != 0,
          off_namecache_nc_vp != 0,
          off_namecache_nc_child_tqe_next != 0 else {
        globallogger.log("(fetchkcache) exploit, self proc/task, or offsets not ready")
        return false
    }

    guard let kcpath = syskcpath() else {
        globallogger.log("(fetchkcache) failed to get kernelcache path")
        return false
    }

    guard let outpath = larakcpath() else {
        globallogger.log("(fetchkcache) failed to get output path")
        return false
    }

    let fakeread = "/private/preboot/Cryptexes/OS/System/Library/CoreServices/RestoreVersion.plist"

    var redirectState = vn_redirect_state_t(orig_vnode: 0, orig_v_data: 0, to_fd: -1, from_fd: -1)

    let redirect = kcpath.withCString { kcCString in
        vn_fileredirect(fakeread, kcCString, &redirectState)
    }
    if !redirect {
        globallogger.log("(fetchkcache) failed to redirect vnode")
        return false
    }

    let src = open(fakeread, O_RDONLY)
    if src < 0 {
        vn_fileunredirect(&redirectState)
        return false
    }

    // Unique sibling temp + O_EXCL — never unlink/open the live Documents path (TOCTOU).
    let tmpPath = outpath + ".lara.\(arc4random()).tmp"
    let dst = open(tmpPath, O_WRONLY | O_CREAT | O_TRUNC | O_EXCL, 0o644)
    if dst < 0 {
        close(src)
        vn_fileunredirect(&redirectState)
        return false
    }

    var published = false
    defer {
        close(src)
        close(dst)
        vn_fileunredirect(&redirectState)
        if !published {
            unlink(tmpPath)
        }
    }

    var buffer = [UInt8](repeating: 0, count: 0x4000)
    let bufferSize = buffer.count
    var totalBytes = 0
    var copyFailed = false

    while true {
        let n = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
            guard let base = rawBuffer.baseAddress else { return -1 }
            return read(src, base, bufferSize)
        }

        if n < 0 {
            globallogger.log("(fetchkcache) failed to read kernelcache")
            copyFailed = true
            break
        }

        if n == 0 {
            break
        }

        var written = 0
        while written < n {
            let w = buffer.withUnsafeBytes { rawBuffer -> Int in
                guard let base = rawBuffer.baseAddress else { return -1 }
                return write(dst, base.advanced(by: written), n - written)
            }

            if w <= 0 {
                globallogger.log("(fetchkcache) failed to write kernelcache")
                copyFailed = true
                break
            }

            written += w
        }
        if copyFailed { break }

        totalBytes += n
    }

    if copyFailed || totalBytes == 0 {
        globallogger.log("(fetchkcache) kernelcache output incomplete — removed truncated file")
        return false
    }
    if fsync(dst) != 0 {
        globallogger.log("(fetchkcache) fsync failed")
        return false
    }

    // Validate magic on the temp before publishing.
    guard let handle = FileHandle(forReadingAtPath: tmpPath) else {
        globallogger.log("(fetchkcache) kernelcache temp missing")
        return false
    }
    let magic = handle.readData(ofLength: 2)
    handle.closeFile()
    guard magic.count == 2, magic[magic.startIndex] == 0x30, magic[magic.index(after: magic.startIndex)] == 0x84 else {
        globallogger.log("(fetchkcache) invalid kernelcache output")
        return false
    }

    if rename(tmpPath, outpath) != 0 {
        globallogger.log("(fetchkcache) rename to final path failed")
        return false
    }
    published = true

    globallogger.log("(fetchkcache) kernelcache fetch success!")
    return true
}
