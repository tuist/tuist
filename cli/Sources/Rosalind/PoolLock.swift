actor PoolLock {
    private let capacity: Int
    private var inUse: Int = 0
    private var waitQueue: [CheckedContinuation<Void, Never>] = []

    init(capacity: Int) {
        self.capacity = capacity
    }

    func acquire() async {
        if inUse < capacity {
            inUse += 1
            rosalindLogger.debug("PoolLock acquire (no wait): inUse=\(inUse)/\(capacity) queued=\(waitQueue.count)")
            return
        }

        rosalindLogger.debug("PoolLock acquire (waiting): inUse=\(inUse)/\(capacity) queued=\(waitQueue.count + 1)")
        await withCheckedContinuation { continuation in
            waitQueue.append(continuation)
        }
        rosalindLogger.debug("PoolLock acquire (resumed): inUse=\(inUse)/\(capacity) queued=\(waitQueue.count)")
    }

    func release() {
        guard inUse > 0 else {
            rosalindLogger.debug("PoolLock release with inUse=0 (ignored)")
            return
        }

        if waitQueue.isEmpty {
            inUse -= 1
            rosalindLogger.debug("PoolLock release: inUse=\(inUse)/\(capacity) queued=0")
        } else {
            let continuation = waitQueue.removeFirst()
            rosalindLogger.debug("PoolLock release: handing off, inUse=\(inUse)/\(capacity) queued=\(waitQueue.count)")
            continuation.resume()
        }
    }
}
