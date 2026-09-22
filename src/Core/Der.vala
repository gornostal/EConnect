/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Minimal DER walker: extracts the SubjectPublicKeyInfo from an X.509
 * certificate. Needed for the pairing verification code, which hashes the
 * public keys of both devices (matching QSslCertificate::publicKey().toDer()).
 *
 *   Certificate ::= SEQUENCE {
 *     tbsCertificate ::= SEQUENCE {
 *       [0] version OPTIONAL, serialNumber INTEGER, signature SEQUENCE,
 *       issuer SEQUENCE, validity SEQUENCE, subject SEQUENCE,
 *       subjectPublicKeyInfo SEQUENCE, ... } ... }
 */
namespace EConnect.Core.Der {

    public errordomain DerError {
        MALFORMED
    }

    private bool read_header (uint8[] data, size_t pos,
                              out uint8 tag, out size_t header_len, out size_t content_len) {
        tag = 0;
        header_len = 0;
        content_len = 0;
        if (pos + 2 > data.length) {
            return false;
        }
        tag = data[pos];
        uint8 first = data[pos + 1];
        if (first < 0x80) {
            header_len = 2;
            content_len = first;
        } else {
            int n = first & 0x7f;
            if (n == 0 || n > 4 || pos + 2 + n > data.length) {
                return false;
            }
            size_t len = 0;
            for (int i = 0; i < n; i++) {
                len = (len << 8) | data[pos + 2 + i];
            }
            header_len = 2 + n;
            content_len = len;
        }
        return pos + header_len + content_len <= data.length;
    }

    private size_t expect (uint8[] data, size_t pos, uint8 want_tag,
                           out size_t header_len, out size_t content_len) throws DerError {
        uint8 tag;
        if (!read_header (data, pos, out tag, out header_len, out content_len) || tag != want_tag) {
            throw new DerError.MALFORMED ("Expected tag 0x%02x at offset %u", want_tag, (uint) pos);
        }
        return pos;
    }

    /** Returns the raw DER of the SubjectPublicKeyInfo structure. */
    public uint8[] subject_public_key_info (uint8[] cert) throws DerError {
        size_t hdr, len;
        size_t pos = 0;

        expect (cert, pos, 0x30, out hdr, out len);   // Certificate
        pos += hdr;
        expect (cert, pos, 0x30, out hdr, out len);   // tbsCertificate
        pos += hdr;

        uint8 tag;
        if (!read_header (cert, pos, out tag, out hdr, out len)) {
            throw new DerError.MALFORMED ("Truncated tbsCertificate");
        }
        if (tag == 0xA0) {                            // [0] version
            pos += hdr + len;
        }

        uint8[] skip_tags = { 0x02, 0x30, 0x30, 0x30, 0x30 }; // serial, sigalg, issuer, validity, subject
        foreach (uint8 t in skip_tags) {
            expect (cert, pos, t, out hdr, out len);
            pos += hdr + len;
        }

        expect (cert, pos, 0x30, out hdr, out len);   // subjectPublicKeyInfo
        return cert[pos : pos + hdr + len];
    }

    /** memcmp-style ordering, then shorter-first (mirrors QByteArray operator<). */
    public int compare (uint8[] a, uint8[] b) {
        size_t n = size_t.min (a.length, b.length);
        int c = Posix.memcmp (a, b, n);
        if (c != 0) {
            return c;
        }
        return a.length - b.length;
    }
}
