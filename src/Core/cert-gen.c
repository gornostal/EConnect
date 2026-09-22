/*
 * SPDX-License-Identifier: MIT
 *
 * Generates the long-lived self-signed RSA certificate that identifies this
 * device, the way KDE Connect does: CN = device id, O = KDE, OU = Kde connect.
 *
 * notBefore is back-dated a year and notAfter set ten years out, so a phone
 * whose clock is behind ours still accepts the certificate. GnuTLS is used
 * directly rather than the openssl CLI because the Flatpak runtime ships the
 * library but not the binary.
 */
#include "cert-gen.h"

#include <gio/gio.h>
#include <glib/gstdio.h>
#include <string.h>
#include <time.h>
#include <gnutls/gnutls.h>
#include <gnutls/x509.h>

#define KEY_BITS 2048
#define BACKDATE_SECONDS (365 * 24 * 60 * 60)
#define LIFETIME_SECONDS (10 * 365 * 24 * 60 * 60L)

static gboolean
fail (GError **error, const gchar *what, int code)
{
    g_set_error (error, G_IO_ERROR, G_IO_ERROR_FAILED,
                 "%s: %s", what, gnutls_strerror (code));
    return FALSE;
}

/* PEM-export a GnuTLS object into path with owner-only permissions. */
static gboolean
write_pem (const gchar *path, const guchar *data, gsize size, GError **error)
{
    if (!g_file_set_contents (path, (const gchar *) data, (gssize) size, error)) {
        return FALSE;
    }
    if (g_chmod (path, 0600) != 0) {
        g_set_error (error, G_IO_ERROR, G_IO_ERROR_FAILED,
                     "Cannot restrict permissions on %s", path);
        return FALSE;
    }
    return TRUE;
}

gboolean
econnect_cert_gen_self_signed (const gchar *key_path,
                               const gchar *cert_path,
                               const gchar *common_name,
                               GError **error)
{
    gnutls_x509_privkey_t key = NULL;
    gnutls_x509_crt_t crt = NULL;
    guchar *key_pem = NULL;
    guchar *crt_pem = NULL;
    gsize key_size = 0;
    gsize crt_size = 0;
    gboolean ok = FALSE;
    time_t now = time (NULL);
    guchar serial[8];
    int rc;

    g_return_val_if_fail (key_path != NULL, FALSE);
    g_return_val_if_fail (cert_path != NULL, FALSE);
    g_return_val_if_fail (common_name != NULL, FALSE);

    if ((rc = gnutls_x509_privkey_init (&key)) < 0) {
        return fail (error, "privkey_init", rc);
    }
    if ((rc = gnutls_x509_crt_init (&crt)) < 0) {
        fail (error, "crt_init", rc);
        goto out;
    }

    if ((rc = gnutls_x509_privkey_generate (key, GNUTLS_PK_RSA, KEY_BITS, 0)) < 0) {
        fail (error, "privkey_generate", rc);
        goto out;
    }

    if ((rc = gnutls_x509_crt_set_key (crt, key)) < 0) {
        fail (error, "crt_set_key", rc);
        goto out;
    }
    if ((rc = gnutls_x509_crt_set_version (crt, 3)) < 0) {
        fail (error, "crt_set_version", rc);
        goto out;
    }

    /* Any unique positive integer will do; the creation time is plenty. */
    for (int i = 0; i < 8; i++) {
        serial[i] = (guchar) ((((gint64) now) >> ((7 - i) * 8)) & 0xff);
    }
    serial[0] &= 0x7f;
    if ((rc = gnutls_x509_crt_set_serial (crt, serial, sizeof (serial))) < 0) {
        fail (error, "crt_set_serial", rc);
        goto out;
    }

    if ((rc = gnutls_x509_crt_set_activation_time (crt, now - BACKDATE_SECONDS)) < 0) {
        fail (error, "crt_set_activation_time", rc);
        goto out;
    }
    if ((rc = gnutls_x509_crt_set_expiration_time (crt, now + LIFETIME_SECONDS)) < 0) {
        fail (error, "crt_set_expiration_time", rc);
        goto out;
    }

    rc = gnutls_x509_crt_set_dn_by_oid (crt, GNUTLS_OID_X520_COMMON_NAME, 0,
                                        common_name, (unsigned) strlen (common_name));
    if (rc < 0) {
        fail (error, "crt_set_dn CN", rc);
        goto out;
    }
    rc = gnutls_x509_crt_set_dn_by_oid (crt, GNUTLS_OID_X520_ORGANIZATION_NAME, 0,
                                        "KDE", 3);
    if (rc < 0) {
        fail (error, "crt_set_dn O", rc);
        goto out;
    }
    rc = gnutls_x509_crt_set_dn_by_oid (crt, GNUTLS_OID_X520_ORGANIZATIONAL_UNIT_NAME, 0,
                                        "Kde connect", 11);
    if (rc < 0) {
        fail (error, "crt_set_dn OU", rc);
        goto out;
    }

    if ((rc = gnutls_x509_crt_sign2 (crt, crt, key, GNUTLS_DIG_SHA256, 0)) < 0) {
        fail (error, "crt_sign", rc);
        goto out;
    }

    /* Two-step export: ask for the size, then for the bytes. */
    rc = gnutls_x509_privkey_export (key, GNUTLS_X509_FMT_PEM, NULL, &key_size);
    if (rc != GNUTLS_E_SHORT_MEMORY_BUFFER) {
        fail (error, "privkey_export size", rc);
        goto out;
    }
    key_pem = g_malloc0 (key_size);
    if ((rc = gnutls_x509_privkey_export (key, GNUTLS_X509_FMT_PEM, key_pem, &key_size)) < 0) {
        fail (error, "privkey_export", rc);
        goto out;
    }

    rc = gnutls_x509_crt_export (crt, GNUTLS_X509_FMT_PEM, NULL, &crt_size);
    if (rc != GNUTLS_E_SHORT_MEMORY_BUFFER) {
        fail (error, "crt_export size", rc);
        goto out;
    }
    crt_pem = g_malloc0 (crt_size);
    if ((rc = gnutls_x509_crt_export (crt, GNUTLS_X509_FMT_PEM, crt_pem, &crt_size)) < 0) {
        fail (error, "crt_export", rc);
        goto out;
    }

    if (!write_pem (key_path, key_pem, key_size, error)) {
        goto out;
    }
    if (!write_pem (cert_path, crt_pem, crt_size, error)) {
        goto out;
    }

    ok = TRUE;

out:
    g_free (key_pem);
    g_free (crt_pem);
    if (crt != NULL) {
        gnutls_x509_crt_deinit (crt);
    }
    if (key != NULL) {
        gnutls_x509_privkey_deinit (key);
    }
    return ok;
}
