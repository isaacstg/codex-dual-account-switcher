#ifndef PROCESS_IDENTITY_H
#define PROCESS_IDENTITY_H
#include <stdint.h>
typedef struct { int32_t pid; uint32_t uid; uint64_t seconds; uint64_t microseconds; char executable[4096]; } DAProcessSnapshot;
// Reads only BSD process metadata and executable path. No argv or environment access.
int da_snapshot(int32_t pid, DAProcessSnapshot *output);
#endif
