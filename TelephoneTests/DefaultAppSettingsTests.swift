//
//  DefaultAppSettingsTests.swift
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

import Testing
import UseCasesTestDoubles

@MainActor
struct DefaultAppSettingsTests {
    @Test func registersDefaultSettingsOnRegister() {
        let settings = SettingsFake()
        let sut = DefaultAppSettings(settings: settings)

        sut.register()

        #expect(!settings.registeredDefaults.isEmpty)
    }

    @Test func automaticCallRecordingIsOffByDefault() {
        let settings = SettingsFake()
        let sut = DefaultAppSettings(settings: settings)

        sut.register()

        #expect(!(settings.registeredDefaults[UserDefaultsKeys.automaticallyRecordCalls] as! Bool))
    }

    @Test func automaticCallRecordingDefaultsToOgg() {
        let settings = SettingsFake()
        let sut = DefaultAppSettings(settings: settings)

        sut.register()

        #expect(settings.registeredDefaults[UserDefaultsKeys.recordingFormat] as? String == "ogg")
    }

    @Test func telephoneNumberFormattingIsOnByDefault() {
        let settings = SettingsFake()
        let sut = DefaultAppSettings(settings: settings)

        sut.register()

        #expect(settings.registeredDefaults[UserDefaultsKeys.formatTelephoneNumbers] as! Bool)
    }

    @Test func lastFourDigitsAreNotSplitByDefault() {
        let settings = SettingsFake()
        let sut = DefaultAppSettings(settings: settings)

        sut.register()

        #expect(!(settings.registeredDefaults[UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits] as! Bool))
    }

    @Test func registeringDefaultsPreservesSavedNumberFormattingChoices() {
        let settings = SettingsFake()
        settings.set(false, forKey: UserDefaultsKeys.formatTelephoneNumbers)
        settings.set(true, forKey: UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits)
        let sut = DefaultAppSettings(settings: settings)

        sut.register()

        #expect(!settings.bool(forKey: UserDefaultsKeys.formatTelephoneNumbers))
        #expect(settings.bool(forKey: UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits))
        #expect(settings.registeredDefaults[UserDefaultsKeys.formatTelephoneNumbers] as? Bool == true)
        #expect(settings.registeredDefaults[UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits] as? Bool == false)
    }
}
