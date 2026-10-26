//
//  LazyDiscardingContactMatchingIndex.swift
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

@ContactsActor
public final class LazyDiscardingContactMatchingIndex {
    private var origin: ContactMatchingIndex?
    private var needsLoad = true
    private var generation: UInt64 = 0
    private var pendingLoad: (generation: UInt64, task: Task<ContactMatchingIndexLoadResult, Never>)?

    public private(set) var loadState: ContactsLoadState = .notLoaded

    private let factory: ContactMatchingIndexFactory
    private let stateDidChange: @Sendable (ContactsLoadState) -> Void

    public nonisolated init(
        factory: ContactMatchingIndexFactory,
        stateDidChange: @escaping @Sendable (ContactsLoadState) -> Void = { _ in }
    ) {
        self.factory = factory
        self.stateDidChange = stateDidChange
    }

    /// Explicit retry and activation/store-change rechecks never request permission themselves.
    public func refresh() async {
        invalidate()
        await createOriginIfNeeded()
    }

    private func createOriginIfNeeded() async {
        while needsLoad {
            let currentGeneration = generation
            let task: Task<ContactMatchingIndexLoadResult, Never>
            if let pendingLoad, pendingLoad.generation == currentGeneration {
                task = pendingLoad.task
            } else {
                setLoadState(.loading)
                task = Task { await factory.make() }
                pendingLoad = (currentGeneration, task)
            }
            let result = await task.value
            guard generation == currentGeneration else { continue }
            guard pendingLoad?.generation == currentGeneration else { continue }
            pendingLoad = nil
            needsLoad = false
            switch result {
            case .success(let index):
                origin = index
                setLoadState(.ready)
            case .failure(let failure):
                // Only a fetch error within the same valid access scope may use the last
                // complete snapshot. Revoked, unknown or narrowed access must clear it.
                if failure != .transient { origin = nil }
                setLoadState(.unavailable(failure))
            }
        }
    }

    private func invalidate() {
        generation &+= 1
        needsLoad = true
        pendingLoad = nil
    }

    private func setLoadState(_ state: ContactsLoadState) {
        guard loadState != state else { return }
        loadState = state
        stateDidChange(state)
    }
}

extension LazyDiscardingContactMatchingIndex: ContactMatchingIndex {
    public func contact(forPhone phone: ExtractedPhoneNumber) async -> MatchedContact? {
        while true {
            await createOriginIfNeeded()
            let currentGeneration = generation
            let result = await origin?.contact(forPhone: phone)
            guard generation == currentGeneration, !needsLoad else { continue }
            return result
        }
    }

    public func contact(forEmail email: NormalizedLowercasedString) async -> MatchedContact? {
        while true {
            await createOriginIfNeeded()
            let currentGeneration = generation
            let result = await origin?.contact(forEmail: email)
            guard generation == currentGeneration, !needsLoad else { continue }
            return result
        }
    }
}

extension LazyDiscardingContactMatchingIndex: ContactsChangeEventTarget {
    public func contactsDidChange() {
        invalidate()
    }
}
