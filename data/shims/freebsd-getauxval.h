#pragma once
#include <sys/auxv.h>
static inline unsigned long getauxval(int type) {
  unsigned long v = 0;
  return elf_aux_info(type, &v, sizeof v) == 0 ? v : 0;
}
