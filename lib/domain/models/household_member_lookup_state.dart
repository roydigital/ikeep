import 'app_user.dart';

class HouseholdMemberLookupState {
  const HouseholdMemberLookupState({
    this.isLoading = false,
    this.searchedEmail = '',
    this.foundUserId,
    this.errorMessage,
    this.foundUser,
  });

  final bool isLoading;
  final String searchedEmail;
  final String? foundUserId;
  final String? errorMessage;
  final AppUser? foundUser;

  bool get hasFoundUser => foundUser != null && foundUserId != null;

  HouseholdMemberLookupState copyWith({
    bool? isLoading,
    String? searchedEmail,
    String? foundUserId,
    String? errorMessage,
    AppUser? foundUser,
    bool clearFoundUser = false,
    bool clearError = false,
  }) {
    return HouseholdMemberLookupState(
      isLoading: isLoading ?? this.isLoading,
      searchedEmail: searchedEmail ?? this.searchedEmail,
      foundUserId: clearFoundUser ? null : (foundUserId ?? this.foundUserId),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      foundUser: clearFoundUser ? null : (foundUser ?? this.foundUser),
    );
  }
}
