/* MIT License
 *
 * Copyright (c) 2016-2020 INRIA, CMU and Microsoft Corporation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include "evercrypt_targetconfig.h"
#include "libintvector.h"
#include "kremlin/internal/types.h"
#include "kremlin/lowstar_endianness.h"
#include <string.h>
#include "kremlin/internal/target.h"

#ifndef __Hacl_Impl_Generic_HKDF_H
#define __Hacl_Impl_Generic_HKDF_H

#include "Hacl_Spec.h"


/* SNIPPET_START: Hacl_Impl_Generic_HKDF_hkdf_extract */

extern void
Hacl_Impl_Generic_HKDF_hkdf_extract(
  K___Spec_Agile_DH_algorithm_Spec_Agile_AEAD_alg_Spec_Hash_Definitions_hash_alg cs,
  uint8_t *x0,
  uint8_t *x1,
  uint32_t x2,
  uint8_t *x3,
  uint32_t x4
);

/* SNIPPET_END: Hacl_Impl_Generic_HKDF_hkdf_extract */

/* SNIPPET_START: Hacl_Impl_Generic_HKDF_hkdf_expand */

extern void
Hacl_Impl_Generic_HKDF_hkdf_expand(
  K___Spec_Agile_DH_algorithm_Spec_Agile_AEAD_alg_Spec_Hash_Definitions_hash_alg cs,
  uint8_t *x0,
  uint8_t *x1,
  uint32_t x2,
  uint8_t *x3,
  uint32_t x4,
  uint32_t x5
);

/* SNIPPET_END: Hacl_Impl_Generic_HKDF_hkdf_expand */

#define __Hacl_Impl_Generic_HKDF_H_DEFINED
#endif