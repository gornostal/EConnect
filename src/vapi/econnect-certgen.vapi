/*
 * SPDX-License-Identifier: MIT
 *
 * Vala binding for src/Core/cert-gen.c.
 */
[CCode (cheader_filename = "cert-gen.h")]
namespace EConnect.CertGen {

    /**
     * Writes a fresh self-signed RSA key and certificate (CN = common_name)
     * to the given paths, readable only by the current user.
     */
    [CCode (cname = "econnect_cert_gen_self_signed")]
    public void self_signed (string key_path, string cert_path, string common_name) throws GLib.Error;
}
