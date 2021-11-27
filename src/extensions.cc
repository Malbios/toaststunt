/******************************************************************************
  Copyright (c) 1995, 1996 Xerox Corporation.  All rights reserved.
  Portions of this code were written by Stephen White, aka ghond.
  Use and copying of this software and preparation of derivative works based
  upon this software are permitted.  Any distribution of this software or
  derivative works must comply with all applicable United States export
  control laws.  This software is made available AS IS, and Xerox Corporation
  makes no warranty about the software, its performance or its conformity to
  any specification.  Any person obtaining a copy of this software is requested
  to send their name and post office or electronic mail address to:
    Pavel Curtis
    Xerox PARC
    3333 Coyote Hill Rd.
    Palo Alto, CA 94304
    Pavel@Xerox.Com
 *****************************************************************************/

/* Extensions to the MOO server

 * This module contains some examples of how to extend the MOO server using
 * some of the interfaces exported by various other modules.  The examples are
 * all commented out, since they're really not all that useful in general; they
 * were written primarily to test out the interfaces they use.
 *
 * The uncommented parts of this module provide a skeleton for any module that
 * implements new MOO built-in functions.  Feel free to replace the
 * commented-out bits with your own extensions; in future releases, you can
 * just replace the distributed version of this file (which will never contain
 * any actually useful code) with your own edited version as a simple way to
 * link in your extensions.
 */

#include "bf_register.h"
#include "functions.h"
#include "db_tune.h"

void register_extensions()
{
}