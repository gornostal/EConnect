/*
 * SPDX-License-Identifier: MIT
 *
 * Self-signed device certificate, generated with GnuTLS. Bound into Vala as
 * EConnect.CertGen.self_signed () by vapi/econnect-certgen.vapi.
 */
#pragma once

#include <glib.h>

G_BEGIN_DECLS

gboolean econnect_cert_gen_self_signed (const gchar *key_path,
                                        const gchar *cert_path,
                                        const gchar *common_name,
                                        GError **error);

G_END_DECLS
