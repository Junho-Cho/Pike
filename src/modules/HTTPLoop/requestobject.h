/*
|| This file is part of Pike. For copyright information see COPYRIGHT.
|| Pike is distributed under GPL, LGPL and MPL. See the file COPYING
|| for more information.
*/

void f_aap_scan_for_query(INT32 args);
void f_aap_index_op(INT32 args);
void f_aap_end(INT32 args);
void f_aap_output(INT32 args);
void f_aap_reply(INT32 args);
void f_aap_reply_with_cache(INT32 args);
void f_low_aap_reqo__init(struct c_request_object *);
void aap_init_request_object(struct object *o);
void aap_exit_request_object(struct object *o);
