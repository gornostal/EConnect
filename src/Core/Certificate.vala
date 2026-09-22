/*
 * SPDX-License-Identifier: MIT
 *
 * Device identity: a long-lived self-signed RSA certificate whose CN is the
 * device id (as KDE Connect does). Generated with GnuTLS in Core/cert-gen.c.
 */
namespace EConnect.Core.Certificate {

    /** 32 hex characters: a UUIDv4 with the dashes removed. */
    public string new_device_id () {
        return GLib.Uuid.string_random ().replace ("-", "");
    }

    public void generate (string key_path, string cert_path, string device_id) throws Error {
        CertGen.self_signed (key_path, cert_path, device_id);
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
