// SPDX-License-Identifier: GPL-3.0-or-later
// Darling Embedded Security.framework (Authorization Services subset).
// There is no security server or authentication UI in this userland, so
// privilege escalation is always refused with errAuthorizationDenied.
#include <stdint.h>

typedef int32_t OSStatus;
typedef struct AuthorizationOpaqueRef* AuthorizationRef;

enum {
  errAuthorizationSuccess = 0,
  errAuthorizationDenied = -60005,
};

OSStatus AuthorizationCreate(const void* rights, const void* environment,
                             uint32_t flags, AuthorizationRef* authorization) {
  (void)rights;
  (void)environment;
  (void)flags;
  if (authorization) *authorization = 0;
  return errAuthorizationDenied;
}

OSStatus AuthorizationCopyRights(AuthorizationRef authorization, const void* rights,
                                 const void* environment, uint32_t flags,
                                 void** authorizedRights) {
  (void)authorization;
  (void)rights;
  (void)environment;
  (void)flags;
  if (authorizedRights) *authorizedRights = 0;
  return errAuthorizationDenied;
}

OSStatus AuthorizationFree(AuthorizationRef authorization, uint32_t flags) {
  (void)authorization;
  (void)flags;
  return errAuthorizationSuccess;
}

OSStatus AuthorizationExecuteWithPrivileges(AuthorizationRef authorization,
                                            const char* path, uint32_t options,
                                            char* const* arguments, void** pipe) {
  (void)authorization;
  (void)path;
  (void)options;
  (void)arguments;
  (void)pipe;
  return errAuthorizationDenied;
}
