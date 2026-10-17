enum AdminRole {
  systemAdmin,
  centralAdmin,
  stationAdmin,
  fieldOfficer,
  standardUser;

  static AdminRole? fromDatabase(String? value) {
    switch (value) {
      case 'system_admin':
      case 'super_admin':
        return AdminRole.systemAdmin;
      case 'central_admin':
        return AdminRole.centralAdmin;
      case 'station_admin':
      case 'admin':
        return AdminRole.stationAdmin;
      case 'field_officer':
        return AdminRole.fieldOfficer;
      case 'standard_user':
        return AdminRole.standardUser;
      default:
        return null;
    }
  }

  String get label {
    switch (this) {
      case AdminRole.systemAdmin:
        return 'System Admin';
      case AdminRole.centralAdmin:
        return 'Central Admin';
      case AdminRole.stationAdmin:
        return 'Station Admin';
      case AdminRole.fieldOfficer:
        return 'Field Officer';
      case AdminRole.standardUser:
        return 'Standard User';
    }
  }

  bool get canAccessAdminPortal => this != AdminRole.standardUser;

  bool get canManageStaff =>
      this == AdminRole.systemAdmin ||
      this == AdminRole.centralAdmin ||
      this == AdminRole.stationAdmin;

  bool get canManageStations =>
      this == AdminRole.systemAdmin || this == AdminRole.centralAdmin;
}
