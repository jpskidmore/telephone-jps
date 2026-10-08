//
//  AccountsMenuItems.swift
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

import Cocoa

@MainActor
final class AccountsMenuItems: NSObject {
    private var items: [NSMenuItem] = []

    private let menu: NSMenu
    private let controllers: AccountControllers

    @objc init(menu: NSMenu, controllers: AccountControllers) {
        self.menu = menu
        self.controllers = controllers
        super.init()
        update()
    }

    @objc func update() {
        removeItemsFromMenu()
        updateItems()
        addItemsToMenu()
    }
}

private extension AccountsMenuItems {
    func removeItemsFromMenu() {
        for item in items {
            menu.removeItem(item)
        }
    }

    func updateItems() {
        items = []
        if !controllers.all.isEmpty {
            let item = NSMenuItem(title: "Dialler", action: #selector(toggleAccountWindow), keyEquivalent: "1")
            item.target = self
            items = [item, NSMenuItem.separator()]
        }
    }

    func addItemsToMenu() {
        let start = indexOfFirstSeparatorItem() + 1
        for (item, index) in zip(items, start..<(start + items.count)) {
            menu.insertItem(item, at: index)
        }
    }

    @objc func toggleAccountWindow(_ item: NSMenuItem) {
        DialPlanCoordinator.shared.showDialler()
    }

    func indexOfFirstSeparatorItem() -> Int {
        guard let firstSeparator = menu.items.first(where:(\.isSeparatorItem)) else { return 0 }
        return menu.index(of: firstSeparator)
    }
}
