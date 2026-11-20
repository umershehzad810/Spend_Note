import 'package:sqflite/sqflite.dart';

String friendlyError(Object error) {
  if (error is FormatException) return error.message;
  if (error is DatabaseException) {
    if (error.isUniqueConstraintError()) {
      return 'A record with these details already exists. Please edit it instead.';
    }
    if (error.isDatabaseClosedError()) {
      return 'Storage is unavailable. Close and reopen SpendNote, then try again.';
    }
    return 'Could not finish saving. Check your records, then try again.';
  }
  return 'Could not complete this action. Please try again.';
}
