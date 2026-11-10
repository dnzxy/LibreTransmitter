//
//  LibreTransmitterAlert.swift
//  LibreTransmitter
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

/// The sensor and transmitter alerts this plugin raises. Glucose alerts are the app's;
/// these cover what only the CGM plugin knows: session timing, a failed or unreadable
/// sensor, a sensor the transmitter can't find, and the transmitter itself.
///
/// The session-timed ones are scheduled ahead with a delayed trigger, so they fire
/// whether or not the app is running when the moment comes.
public enum LibreTransmitterAlert: String, CaseIterable {
    /// 24 hours before the sensor's wear time ends.
    case sensorExpiringSoon
    /// 2 hours before the sensor's wear time ends.
    case sensorExpiringImminently
    /// End of wear time; readings stop.
    case sensorExpired
    case sensorFailed
    /// The sensor can't be read: not started, or not a supported type.
    case sensorInvalid
    /// The transmitter reports no sensor underneath it.
    case sensorNotDetected
    /// The transmitter found a new sensor.
    case sensorChanged
    case noTransmitterSelected
    case transmitterBatteryLow

    static let expiringSoonLeadTime = TimeInterval(hours: 24)
    static let expiringImminentlyLeadTime = TimeInterval(hours: 2)
    static let lowBatteryPercent = 20

    /// The alerts whose timing follows the sensor's wear time, (re)scheduled together.
    static let sessionTimed: [LibreTransmitterAlert] = [.sensorExpiringSoon, .sensorExpiringImminently, .sensorExpired]

    func identifier(managerIdentifier: String) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: rawValue)
    }

    /// Reminders you can act on in your own time are `.active`; things that have stopped,
    /// or are about to stop, readings interrupt; a sensor that has to be replaced is critical.
    var interruptionLevel: Alert.InterruptionLevel {
        switch self {
        case .sensorExpiringSoon:
            return .active
        case .sensorExpiringImminently, .sensorExpired, .sensorInvalid, .sensorNotDetected, .sensorChanged, .noTransmitterSelected,
             .transmitterBatteryLow:
            return .timeSensitive
        case .sensorFailed:
            return .critical
        }
    }

    var title: String {
        switch self {
        case .sensorExpiringSoon:
            return LocalizedString("Sensor Expires in 24 Hours", comment: "Alert title 24 hours before sensor expiry")
        case .sensorExpiringImminently:
            return LocalizedString("Sensor Expires in 2 Hours", comment: "Alert title 2 hours before sensor expiry")
        case .sensorExpired:
            return LocalizedString("Sensor Expired", comment: "Alert title at sensor expiry")
        case .sensorFailed:
            return LocalizedString("Sensor Failed", comment: "Alert title for a failed sensor")
        case .sensorInvalid:
            return LocalizedString("Sensor Can't Be Read", comment: "Alert title for a sensor that is not started or not supported")
        case .sensorNotDetected:
            return LocalizedString("No Sensor Detected", comment: "Alert title when the transmitter finds no sensor")
        case .sensorChanged:
            return LocalizedString("New Sensor Detected", comment: "Alert title when the transmitter finds a new sensor")
        case .noTransmitterSelected:
            return LocalizedString("No Transmitter Selected", comment: "Alert title when no transmitter or sensor is selected")
        case .transmitterBatteryLow:
            return LocalizedString("Transmitter Battery Low", comment: "Alert title for low transmitter battery")
        }
    }

    var body: String {
        switch self {
        case .sensorExpiringSoon:
            return LocalizedString("Your sensor ends in about a day. Have a new sensor ready.", comment: "Alert body 24 hours before sensor expiry")
        case .sensorExpiringImminently:
            return LocalizedString("Your sensor ends in about 2 hours. Change your sensor soon to avoid a gap in readings.", comment: "Alert body 2 hours before sensor expiry")
        case .sensorExpired:
            return LocalizedString("Your sensor has ended and readings have stopped. Apply and set up a new sensor. Check your glucose with a meter in the meantime.", comment: "Alert body at sensor expiry")
        case .sensorFailed:
            return LocalizedString("Your sensor has stopped working and is not sending readings. Remove it and apply a new sensor. Check your glucose with a meter in the meantime.", comment: "Alert body for a failed sensor")
        case .sensorInvalid:
            return LocalizedString("Your transmitter found a sensor it can't read. The sensor may not be started yet, or it may be a type that isn't supported. No readings will arrive until this is fixed. Check your glucose with a meter in the meantime.", comment: "Alert body for a sensor that is not started or not supported")
        case .sensorNotDetected:
            return LocalizedString("Your transmitter can't find a sensor. Check that the transmitter sits firmly over your sensor. This can be brief; readings resume once the sensor is found again.", comment: "Alert body when the transmitter finds no sensor")
        case .sensorChanged:
            return LocalizedString("Your transmitter found a new sensor. Readings start once it has warmed up, which usually takes about an hour. Check your glucose with a meter in the meantime.", comment: "Alert body when the transmitter finds a new sensor")
        case .noTransmitterSelected:
            return LocalizedString("No transmitter or sensor is selected, so no readings can arrive. Open the CGM settings, delete this CGM and set it up again.", comment: "Alert body when no transmitter or sensor is selected")
        case .transmitterBatteryLow:
            return LocalizedString("Your transmitter's battery is low. Charge or replace it soon so readings don't stop.", comment: "Alert body for low transmitter battery")
        }
    }

    func alert(managerIdentifier: String, trigger: Alert.Trigger = .immediate) -> Alert {
        let content = Alert.Content(
            title: title,
            body: body,
            acknowledgeActionButtonLabel: LocalizedString("OK", comment: "Alert acknowledgment button label")
        )
        return Alert(
            identifier: identifier(managerIdentifier: managerIdentifier),
            foregroundContent: content,
            backgroundContent: content,
            trigger: trigger,
            interruptionLevel: interruptionLevel
        )
    }
}

// MARK: - Alerts
extension LibreTransmitterManagerV3 {

    public static var alertCatalog: [AlertCatalogEntry] {
        LibreTransmitterAlert.allCases.map {
            AlertCatalogEntry(identifier: $0.rawValue, interruptionLevel: $0.interruptionLevel, title: $0.title)
        }
    }

    public func hasAlertCondition(_ alert: LibreTransmitterAlert) -> Bool {
        activeAlertConditions.value.contains(alert)
    }

    /// Readings stopped because the sensor reached the end of its wear time.
    public var isSensorExpired: Bool {
        if let state = lastSensorState.value, state == .expired || state == .shutdown {
            return true
        }
        if let expiresAt = UserDefaults.standard.sensorExpiresAt {
            return expiresAt <= Date()
        }
        return false
    }

    public var isSensorWarmingUp: Bool {
        lastSensorState.value == .starting || hasAlertCondition(.sensorChanged)
    }

    /// Records whether a condition holds. The alert is issued once when it starts (if `isEnabled`)
    /// and retracted when it clears.
    func setAlertCondition(_ alert: LibreTransmitterAlert, isActive: Bool, isEnabled: Bool = true) {
        var changed = false
        activeAlertConditions.mutate { conditions in
            changed = isActive ? conditions.insert(alert).inserted : conditions.remove(alert) != nil
            if changed {
                UserDefaults.standard.activeAlertConditions = conditions.map(\.rawValue)
            }
        }
        guard changed else {
            return
        }

        if !isActive {
            retractAlerts([alert])
        } else if isEnabled {
            issueAlerts([(alert, .immediate)])
        } else {
            logger.info("Alert \(alert.rawValue) is turned off in settings, not issuing it")
        }
        notifyStatusDidChange()
    }

    func setSensorState(_ state: SensorState?) {
        let oldState = lastSensorState.value
        lastSensorState.value = state
        if oldState != state {
            notifyStatusDidChange()
        }
    }

    /// (Re)schedules the session-timed alerts for this sensor. Cheap to call on every reading:
    /// nothing is issued unless the sensor or its end time changed. A sensor first seen already
    /// ended gets the expired alert right away, once.
    func scheduleExpiryAlertsIfNeeded(sensorId: String, expiresAt: Date) {
        let defaults = UserDefaults.standard
        let now = Date()
        if defaults.expiryAlertsSensor == sensorId, let scheduledExpiresAt = defaults.sensorExpiresAt,
           expiresAt <= now || abs(scheduledExpiresAt.timeIntervalSince(expiresAt)) < .minutes(15) {
            return
        }
        defaults.expiryAlertsSensor = sensorId
        defaults.sensorExpiresAt = expiresAt

        var alerts: [(LibreTransmitterAlert, Alert.Trigger)] = []
        if defaults.mmAlertWillSoonExpire {
            let reminders: [(LibreTransmitterAlert, TimeInterval)] = [
                (.sensorExpiringSoon, LibreTransmitterAlert.expiringSoonLeadTime),
                (.sensorExpiringImminently, LibreTransmitterAlert.expiringImminentlyLeadTime)
            ]
            for (alert, leadTime) in reminders {
                let delay = expiresAt.addingTimeInterval(-leadTime).timeIntervalSince(now)
                if delay > 0 {
                    alerts.append((alert, .delayed(interval: delay)))
                }
            }
        }
        let delay = expiresAt.timeIntervalSince(now)
        alerts.append((.sensorExpired, delay > 0 ? .delayed(interval: delay) : .immediate))

        logger.info("Scheduling sensor expiry alerts, sensor ends at \(expiresAt)")
        issueAlerts(alerts, retractingFirst: LibreTransmitterAlert.sessionTimed)
        notifyStatusDidChange()
    }

    func retractAllAlerts() async {
        activeAlertConditions.value = []
        UserDefaults.standard.activeAlertConditions = []
        UserDefaults.standard.expiryAlertsSensor = nil
        UserDefaults.standard.sensorExpiresAt = nil
        let delegate = cgmManagerDelegate
        for alert in LibreTransmitterAlert.allCases {
            await delegate?.retractAlert(identifier: alert.identifier(managerIdentifier: pluginIdentifier))
        }
    }

    public func delete() async {
        await retractAllAlerts()
        await cgmManagerDelegate?.cgmManagerWantsDeletion(self)
    }

    private func issueAlerts(_ alerts: [(LibreTransmitterAlert, Alert.Trigger)], retractingFirst retractions: [LibreTransmitterAlert] = []) {
        let managerIdentifier = pluginIdentifier
        for (alert, trigger) in alerts {
            if case .delayed(let interval) = trigger {
                logDeviceCommunication("Scheduling alert \(alert.rawValue) in \(Int(interval))s", type: .connection)
            } else {
                logDeviceCommunication("Issuing alert \(alert.rawValue)", type: .connection)
            }
        }
        // One task, so the retractions land before the new alerts.
        delegate.notify { delegate in
            Task {
                for alert in retractions {
                    await delegate?.retractAlert(identifier: alert.identifier(managerIdentifier: managerIdentifier))
                }
                for (alert, trigger) in alerts {
                    await delegate?.issueAlert(alert.alert(managerIdentifier: managerIdentifier, trigger: trigger))
                }
            }
        }
    }

    private func retractAlerts(_ alerts: [LibreTransmitterAlert]) {
        let managerIdentifier = pluginIdentifier
        for alert in alerts {
            logDeviceCommunication("Retracting alert \(alert.rawValue)", type: .connection)
        }
        delegate.notify { delegate in
            Task {
                for alert in alerts {
                    await delegate?.retractAlert(identifier: alert.identifier(managerIdentifier: managerIdentifier))
                }
            }
        }
    }

    /// Lets the app re-read the status highlight, which has no reading of its own to trigger it.
    private func notifyStatusDidChange() {
        delegate.notify { [weak self] delegate in
            guard let self else {
                return
            }
            delegate?.cgmManagerDidUpdateState(self)
            delegate?.cgmManager(self, didUpdate: self.cgmManagerStatus)
        }
    }
}
