import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<bool> checkAndRequestPermissions() async {
    try {
      // Check current permissions
      bool locationGranted = await Permission.locationWhenInUse.isGranted;
      bool bluetoothScanGranted = true;
      bool bluetoothAdvertiseGranted = true;
      bool bluetoothConnectGranted = true;

      // For Android 12+, check new Bluetooth permissions
      if (await _isAndroid12OrHigher()) {
        bluetoothScanGranted = await Permission.bluetoothScan.isGranted;
        bluetoothAdvertiseGranted =
            await Permission.bluetoothAdvertise.isGranted;
        bluetoothConnectGranted = await Permission.bluetoothConnect.isGranted;
      }

      if (locationGranted &&
          bluetoothScanGranted &&
          bluetoothAdvertiseGranted &&
          bluetoothConnectGranted) {
        return true;
      }

      // Request missing permissions
      Map<Permission, PermissionStatus> permissions = {};

      if (!locationGranted) {
        permissions[Permission.locationWhenInUse] =
            await Permission.locationWhenInUse.request();
      }

      if (await _isAndroid12OrHigher()) {
        if (!bluetoothScanGranted) {
          permissions[Permission.bluetoothScan] =
              await Permission.bluetoothScan.request();
        }
        if (!bluetoothAdvertiseGranted) {
          permissions[Permission.bluetoothAdvertise] =
              await Permission.bluetoothAdvertise.request();
        }
        if (!bluetoothConnectGranted) {
          permissions[Permission.bluetoothConnect] =
              await Permission.bluetoothConnect.request();
        }
      }

      return permissions.values.every((status) => status.isGranted);
    } catch (e) {
      return false;
    }
  }

  static Future<bool> _isAndroid12OrHigher() async {
    return true; // Simplified - assume Android 12+ for safety
  }
}
