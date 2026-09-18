#ifndef LOCK_FREE_QUEUE_H
#define LOCK_FREE_QUEUE_H

#include <atomic>
#include <cstdint>
#include <cstddef>
#include <new>

// A cacheline-aligned Single-Producer Single-Consumer (SPSC) lock-free ring buffer
// Guarantees zero memory allocation and wait-free execution on the real-time audio thread.
template <typename T, size_t Capacity>
class LockFreeQueue {
    static_assert((Capacity & (Capacity - 1)) == 0, "Capacity must be a power of 2");

public:
    LockFreeQueue() : head_(0), tail_(0) {}

    bool push(const T& item) {
        const size_t currentTail = tail_.load(std::memory_order_relaxed);
        const size_t currentHead = head_.load(std::memory_order_acquire);

        if ((currentTail - currentHead) >= Capacity) {
            return false; // Queue full
        }

        buffer_[currentTail & BufferMask] = item;
        tail_.store(currentTail + 1, std::memory_order_release);
        return true;
    }

    bool pop(T& item) {
        const size_t currentHead = head_.load(std::memory_order_relaxed);
        const size_t currentTail = tail_.load(std::memory_order_acquire);

        if (currentHead == currentTail) {
            return false; // Queue empty
        }

        item = buffer_[currentHead & BufferMask];
        head_.store(currentHead + 1, std::memory_order_release);
        return true;
    }

    bool isEmpty() const {
        return head_.load(std::memory_order_relaxed) == tail_.load(std::memory_order_relaxed);
    }

private:
    static constexpr size_t BufferMask = Capacity - 1;
    alignas(64) std::atomic<size_t> head_;
    alignas(64) std::atomic<size_t> tail_;
    alignas(64) T buffer_[Capacity];
};

#endif // LOCK_FREE_QUEUE_H
