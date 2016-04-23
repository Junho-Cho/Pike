#pike __REAL_VERSION__
#pragma strict_types

//!
//! Base class for cryptographic signature algorithms.
//!
//! Typical classes implementing this API are @[Crypto.RSA], @[Crypto.DSA] and
//! @[Crypto.ECC.Curve.ECDSA].
//!

//! Returns the printable name of the signing algorithm.
string(7bit) name();

//! Returns the number of bits in the private key.
int(0..) key_size();

//! Check whether the public key is the same in
//! two objects.
//!
//! @note
//!   This function differs from @[_equal()] in that only the
//!   public key is regarded, and that it only needs to regard
//!   objects implementing @[Crypto.Sign].
//!
//! @seealso
//!   @[_equal()]
int(0..1) public_key_equal(this_program other);

//! Check whether two objects are equvivalent.
//!
//! This includes checking both the public and private keys.
//!
//! @seealso
//!   @[public_key_equal()]
protected int(0..1) _equal(mixed x);

// PKCS-1
#define Sequence Standards.ASN1.Types.Sequence

//! Signs the @[message] with a PKCS-1 signature using hash algorithm
//! @[h].
string(8bit) pkcs_sign(string(8bit) message, .Hash h);

//! Verify PKCS-1 signature @[sign] of message @[message] using hash
//! algorithm @[h].
int(0..1) pkcs_verify(string(8bit) message, .Hash h, string(8bit) sign);

//! Returns the PKCS-1 algorithm identifier for the signing algorithm with
//! the provided hash algorithm.
Sequence pkcs_signature_algorithm_id(.Hash hash);

//! Returns the PKCS-1 AlgorithmIdentifier.
Sequence pkcs_algorithm_identifier();

//! Creates a SubjectPublicKeyInfo ASN.1 sequence for the object.
//! See RFC 5280 section 4.1.2.7.
Sequence pkcs_public_key();

//! Signs the @[message] with a JOSE JWS signature using hash
//! algorithm @[h].
//!
//! @param message
//!   Message to sign.
//!
//! @param headers
//!   JOSE headers to use. Typically a mapping with a single element
//!   @expr{"typ"@}.
//!
//! @param h
//!   Hash algorithm to use. Valid hashes depend on the signature
//!   algorithm.
//!
//! @returns
//!   Returns the signature on success, and @expr{0@} (zero)
//!   on failure (typically that either the hash algorithm
//!   is invalid for this signature algorithm),
//!
//! @seealso
//!   @[jose_decode()], @[pkcs_sign()], @rfc{7515@}
string(7bit) jose_sign(string(8bit) message,
		       mapping(string(7bit):string(7bit)|int)|void headers,
		       .Hash|void h)
{
  return 0;
}

//! Verify and decode a JOSE JWS signed value.
//!
//! @param jws
//!   A JSON Web Signature as returned by @[jose_sign()].
//!
//! @returns
//!   Returns @expr{0@} (zero) on failure, and an array
//!   @array
//!     @item mapping(string(7bit):string(7bit)|int) 0
//!       The JOSE header.
//!     @item string(8bit) 1
//!       The signed message.
//!   @endarray
//!
//! @seealso
//!   @[jose_sign()], @[pkcs_verify()], @rfc{7515@}
array(mapping(string(7bit):string(7bit)|int)|
      string(8bit)) jose_decode(string(7bit) jws)
{
  return 0;
}

#undef Sequence
