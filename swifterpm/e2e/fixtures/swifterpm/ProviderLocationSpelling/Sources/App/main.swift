import Atomics

print(ManagedAtomic<Int>(0).load(ordering: .relaxed))
