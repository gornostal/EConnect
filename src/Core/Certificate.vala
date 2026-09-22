/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Device identity: a long-lived self-signed RSA certificate whose CN is the
 * device id (as KDE Connect does). Generated with the openssl CLI so no TLS
 * development headers are required to build. TODO: switch to GnuTLS once
 * libgnutls28-dev is part of the build so notBefore can be back-dated.
 */
namespace EConnect.Core.Certificate {

    /** 32 hex characters: a UUIDv4 with the dashes removed. */
    public string new_device_id () {
        return GLib.Uuid.string_random ().replace ("-", "");
    }

    public void generate (string key_path, string cert_path, string device_id) throws Error {
        var proc = new Subprocess (
            SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE,
            "openssl", "req", "-x509",
            "-newkey", "rsa:2048", "-nodes",
            "-keyout", key_path,
            "-out", cert_path,
            "-days", "3650",
            "-subj", "/CN=%s/O=KDE/OU=Kde connect".printf (device_id)
        );
        string? err;
        proc.communicate_utf8 (null, null, null, out err);
        if (!proc.get_successful ()) {
            throw new IOError.FAILED ("openssl failed: %s", err ?? "unknown error");
        }
        FileUtils.chmod (key_path, 0600);
        FileUtils.chmod (cert_path, 0600);
    }

    /** DER bytes of the certificate. */
    public uint8[] der (TlsCertificate cert) {
        return cert.certificate.data;
    }

    public uint8[] public_key_der (TlsCertificate cert) throws Der.DerError {
        return Der.subject_public_key_info (cert.certificate.data);
    }

    /** SHA-256 fingerprint as lowercase hex, for display. */
    public string fingerprint (TlsCertificate cert) {
        var cs = new Checksum (ChecksumType.SHA256);
        uint8[] d = cert.certificate.data;
        cs.update (d, d.length);
        return cs.get_string ();
    }
}
