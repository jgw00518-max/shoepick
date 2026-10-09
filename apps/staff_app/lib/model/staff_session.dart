class StaffRoleAssignment {
  const StaffRoleAssignment({required this.code, required this.name});

  final String code;
  final String name;

  factory StaffRoleAssignment.fromJson(Map<String, dynamic> json) =>
      StaffRoleAssignment(
        code: json['roleCode'] as String,
        name: json['roleName'] as String,
      );
}

class StaffBranch {
  const StaffBranch({
    required this.id,
    required this.code,
    required this.name,
    required this.districtCode,
  });

  final int id;
  final String code;
  final String name;
  final String districtCode;

  factory StaffBranch.fromJson(Map<String, dynamic> json) => StaffBranch(
    id: json['branchId'] as int,
    code: json['branchCode'] as String,
    name: json['branchName'] as String,
    districtCode: json['districtCode'] as String,
  );
}

class StaffProfile {
  const StaffProfile({
    required this.id,
    required this.code,
    required this.name,
    required this.roles,
    required this.branches,
  });

  final int id;
  final String code;
  final String name;
  final List<StaffRoleAssignment> roles;
  final List<StaffBranch> branches;

  factory StaffProfile.fromJson(Map<String, dynamic> json) => StaffProfile(
    id: json['employeeId'] as int,
    code: json['employeeCode'] as String,
    name: json['employeeName'] as String,
    roles: (json['roles'] as List<dynamic>)
        .map(
          (role) => StaffRoleAssignment.fromJson(role as Map<String, dynamic>),
        )
        .toList(),
    branches: (json['branches'] as List<dynamic>)
        .map((branch) => StaffBranch.fromJson(branch as Map<String, dynamic>))
        .toList(),
  );
}

class StaffAuthException implements Exception {
  const StaffAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
