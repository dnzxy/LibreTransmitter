//
//  NotificationHelper.swift
//  MiaomiaoClient
//
//  Created by LoopKit Authors on 30/05/2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import UserNotifications
import os.log

private var logger = Logger(forType: "NotificationHelper")
// MARK: - Notification Utilities
public enum NotificationHelper {

    private enum Identifiers: String {
        case invalidChecksum = "com.loopkit.libremiaomiao.invalidChecksum-notification"
        case calibrationOngoing = "com.loopkit.libremiaomiao.calibration-notification"
        case libre2directFinishedSetup = "com.loopkit.libremiaomiao.libre2direct-notification"
    }
    
    private static func ensureCanSendNotification(_ completion: @escaping () -> Void ) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                logger.debug("\(#function) failed, authorization denied")
                return
            }
            logger.debug("\(#function) sending notification was allowed")

            completion()
        }
    }

    private static func addRequest(identifier: Identifiers, content: UNMutableNotificationContent, deleteOld: Bool = false, interruptionLevel: UNNotificationInterruptionLevel = .timeSensitive) {
        let center = UNUserNotificationCenter.current()
        content.interruptionLevel = interruptionLevel
        
        let request = UNNotificationRequest(identifier: identifier.rawValue, content: content, trigger: nil)

        if deleteOld {
            // Required since ios12+ have started to cache/group notifications
            center.removeDeliveredNotifications(withIdentifiers: [identifier.rawValue])
            center.removePendingNotificationRequests(withIdentifiers: [identifier.rawValue])
        }

        center.add(request) { error in
            if let error {
                logger.debug("\(#function) unable to addNotificationRequest: \(error.localizedDescription)")
                return
            }

            logger.debug("\(#function) sending \(identifier.rawValue) notification")
        }
    }
    
}

// MARK: Sensor related notification sendouts
public extension NotificationHelper {
    static func sendLibre2DirectFinishedSetupNotifcation() {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = "Libre 2 Direct Setup Complete"
            content.body = "Establishing initial connection can take up to 4 minutes. Keep your phone unlocked and Loop in the foreground while connecting"

            addRequest(identifier: .libre2directFinishedSetup, content: content, interruptionLevel: .active)
        }
    }
    
    enum CalibrationMessage: String {
        case invalidCalibrationData = "Could not calibrate sensor, invalid calibrationdata"
        case success = "Success!"
    }

    static func sendCalibrationNotification(_ calibrationMessage: CalibrationMessage) {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.sound = .default
            content.title = "Extracting calibrationdata from sensor"
            content.body = calibrationMessage.rawValue

            addRequest(identifier: .calibrationOngoing,
                       content: content,
                       deleteOld: true,
                       interruptionLevel: .active)
        }
    }
}

// MARK: - Notification sendout
public extension NotificationHelper {
   

    static func sendInvalidChecksumIfDeveloper(_ sensorData: SensorData) {
        guard UserDefaults.standard.dangerModeActivated else {
            return
        }

        if sensorData.hasValidCRCs {
            return
        }

        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = "Invalid libre checksum"
            content.body = "Libre sensor was incorrectly read, CRCs were not valid"

            addRequest(identifier: .invalidChecksum, content: content)
        }
    }

}
