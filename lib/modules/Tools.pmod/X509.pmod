#pike __REAL_VERSION__

/* 
 * $Id: X509.pmod,v 1.20 2003/12/03 10:03:29 nilsson Exp $
 *
 * Some random functions for creating RFC-2459 style X.509 certificates.
 *
 */

#if constant(Standards.ASN1.Types.Sequence)

import Standards.ASN1.Types;
import Standards.PKCS;

// Note: Redump this module if you change X509_DEBUG
#ifdef X509_DEBUG
#define X509_WERR werror
#else
#define X509_WERR
#endif

//! Creates a @[Standards.ASN1.Types.UTC] object from the posix
//! time @[t].
UTC make_time(int t)
{
  Calendar.Second second = Calendar.Second(t)->set_timezone("UTC");

  if (second->year_no() >= 2050)
    error( "Times later than 2049 not supported yet\n" );

  return UTC(sprintf("%02d%02d%02d%02d%02d%02dZ",
		     second->year_no() % 100,
		     second->month_no(),
		     second->month_day(),
		     second->hour_no(),
		     second->minute_no(),
		     second->second_no()));
}

//! Returns a mapping similar to that returned by gmtime
//! @returns
//!   @mapping
//!     @member int "year"
//!     @member int "mon"
//!     @member int "mday"
//!     @member int "hour"
//!     @member int "min"
//!     @member int "sec"
//!   @endmapping
mapping(string:int) parse_time(UTC asn1)
{
  if ((asn1->type_name != "UTCTime")
      || (sizeof(asn1->value) != 13))
    return 0;

  sscanf(asn1->value, "%[0-9]s%c", string s, int c);
  if ( (sizeof(s) != 12) && (c != 'Z') )
    return 0;

  /* NOTE: This relies on pike-0.7 not interpreting leading zeros as
   * an octal prefix. */
  mapping m = mkmapping( ({ "year", "mon", "mday", "hour", "min", "sec" }),
			 (array(int)) (s/2));

  if (m->year < 50)
    m->year += 100;
  if ( (m->mon <= 0 ) || (m->mon > 12) )
    return 0;
  m->mon--;
  
  if ( (m->mday <= 0) || (m->mday > Calendar.ISO.Year(m->year + 1900)
			  ->month(m->mon + 1)->number_of_days()))
    return 0;

  if ( (m->hour < 0) || (m->hour > 23))
    return 0;

  if ( (m->min < 0) || (m->min > 59))
    return 0;

  /* NOTE: Allows for leap seconds */
  if ( (m->sec < 0) || (m->sec > 60))
    return 0;

  return m;
}

//! Comparision function between two "date" mappings of the
//! kind that @[parse_time] returns.
int(-1..1) time_compare(mapping(string:int) t1, mapping(string:int) t2)
{
  foreach( ({ "year", "mon", "mday", "hour", "min", "sec" }), string name)
    if (t1[name] < t2[name])
      return -1;
    else if (t1[name] > t2[name])
      return 1;
  return 0;
}


MetaExplicit extension_sequence = MetaExplicit(2, 3);
MetaExplicit version_integer = MetaExplicit(2, 0);

Sequence rsa_md2_algorithm = Sequence( ({ Identifiers.rsa_md2_id, Null() }) );

Sequence rsa_md5_algorithm = Sequence( ({ Identifiers.rsa_md5_id, Null() }) );

Sequence rsa_sha1_algorithm = Sequence( ({ Identifiers.rsa_sha1_id,
					   Null() }) );

//!
Sequence make_tbs(object issuer, object algorithm,
		object subject, object keyinfo,
		object serial, int ttl,
		array extensions)
{
  int now = time();
  Sequence validity = Sequence( ({ make_time(now), make_time(now + ttl) }) );

  return (extensions
	  ? Sequence( ({ version_integer(Integer(2)), /* Version 3 */
			 serial,
			 algorithm,
			 issuer,
			 validity,
			 subject,
			 keyinfo,
			 extension_sequence(extensions) }) )
	  : Sequence( ({ serial,
			 algorithm,
			 issuer,
			 validity,
			 subject,
			 keyinfo }) ));
}

//!
string make_selfsigned_dsa_certificate(object dsa, int ttl, array name,
				       array|void extensions)
{
  Integer serial = Integer(1); /* Hard coded serial number */
  int now = time();
  Sequence validity = Sequence( ({ make_time(now), make_time(now + ttl) }) );

  Sequence signature_algorithm = Sequence( ({ Identifiers.dsa_sha_id }) );
  
  Sequence keyinfo = Sequence(
    ({ /* Use an identifier with parameters */
       DSA.algorithm_identifier(dsa),
       BitString(DSA.public_key(dsa)) }) );

  Sequence dn = Certificate.build_distinguished_name(@name);
  
  Sequence tbs = make_tbs(dn, signature_algorithm,
			  dn, keyinfo,
			  serial, ttl, extensions);
  
  return Sequence(
    ({ tbs,
       signature_algorithm,
       BitString(dsa->sign_ssl(tbs->get_der())) }))->get_der();
}

//!
string rsa_sign_digest(object rsa, object digest_id, string digest)
{
  Sequence digest_info = Sequence( ({ Sequence( ({ digest_id, Null() }) ),
				      OctetString(digest) }) );
  return rsa->raw_sign(digest_info->get_der())->digits(256);
}

//!
int rsa_verify_digest(object rsa, object digest_id, string digest, string s)
{
  Sequence digest_info = Sequence( ({ Sequence( ({ digest_id, Null() }) ),
					 OctetString(digest) }) );
  return rsa->raw_verify(digest_info->get_der(), Gmp.mpz(s, 256));
}

//!
string make_selfsigned_rsa_certificate(object rsa, int ttl, array name,
				       array|void extensions)
{
  Integer serial = Integer(1); /* Hard coded serial number */

  int now = time();
  Sequence validity = Sequence( ({ make_time(now), make_time(now + ttl) }) );

  Sequence signature_algorithm = Sequence( ({ Identifiers.rsa_sha1_id,
					      Null() }) );

  Sequence keyinfo = Sequence(
    ({ Sequence( ({ Identifiers.rsa_id, Null() }) ),
       BitString(RSA.public_key(rsa)) }) );

  Sequence dn = Certificate.build_distinguished_name(@name);
  
  Sequence tbs = make_tbs(dn, rsa_sha1_algorithm,
			  dn, keyinfo,
			  serial, ttl, extensions);

  return Sequence(
    ({ tbs,
       rsa_sha1_algorithm,
       BitString(rsa_sign_digest(rsa, Identifiers.sha1_id,
#if constant(Crypto.SHA.name)
				 Crypto.SHA.hash(tbs->get_der())
#else
				 Crypto.sha()->update(tbs->get_der())->digest()
#endif
				 )) }) )->get_der();
}

//!
class rsa_verifier
{
  object rsa;

  constant type = "rsa";

  //!
  object init(string key)
  {
    rsa = RSA.parse_public_key(key);
    return rsa && this_object();
  }

  //!
  int verify(object algorithm, string msg, string signature)
  {
    if (algorithm->get_der() == rsa_md5_algorithm->get_der())
      return rsa_verify_digest(rsa, Identifiers.md5_id,
#if constant(Crypto.MD5.name)
			       Crypto.MD5.hash(msg),
#else
			       Crypto.md5()->update(msg)->digest(),
#endif
			       signature);
    if (algorithm->get_der() == rsa_sha1_algorithm->get_der())
      return rsa_verify_digest(rsa, Identifiers.sha1_id,
#if constant(Crypto.SHA.name)
			       Crypto.SHA.hash(msg),
#else
			       Crypto.sha()->update(msg)->digest(),
#endif
			       signature);
    if (algorithm->get_der() == rsa_md2_algorithm->get_der())
      return rsa_verify_digest(rsa, Identifiers.md2_id,
#if constant(Crypto.MD2.name)
			       Crypto.MD2.hash(msg),
#else
			       Crypto.md2()->update(msg)->digest(),
#endif
			       signature);
    return 0;
  }
}

#if 0
/* FIXME: This is a little more difficult, as the dsa-parameters are
 * sometimes taken from the CA, and not present in the keyinfo. */
class dsa_verifier
{
  object dsa;

  constant type = "dsa";

  object init(string key)
    {
    }
}
#endif

//!
rsa_verifier make_verifier(object keyinfo)
{
  if ( (keyinfo->type_name != "SEQUENCE")
       || (sizeof(keyinfo->elements) != 2)
       || (keyinfo->elements[0]->type_name != "SEQUENCE")
       || !sizeof(keyinfo->elements[0]->elements)
       || (keyinfo->elements[1]->type_name != "BIT STRING")
       || keyinfo->elements[1]->unused)
    return 0;
  
  if (keyinfo->elements[0]->elements[0]->get_der()
      == Identifiers.rsa_id->get_der())
  {
    if ( (sizeof(keyinfo->elements[0]->elements) != 2)
	 || (keyinfo->elements[0]->elements[1]->get_der()
	     != Null()->get_der()))
      return 0;
    
    return rsa_verifier()->init(keyinfo->elements[1]->value);
  }

  if(keyinfo->elements[0]->elements[0]->get_der()
      == Identifiers.dsa_sha_id->get_der())
  {
    /* FIXME: Not implemented */
    return 0;
  }
}

//!
class TBSCertificate
{
  string der;
  
  int version;
  object serial;
  object algorithm;  /* Algorithm Identifier */
  object issuer;
  mapping not_after;
  mapping not_before;

  object subject;
  object public_key;

  /* Optional */
  object issuer_id;
  object subject_id;
  object extensions;

  this_program init(Object asn1)
  {
    der = asn1->get_der();
    if (asn1->type_name != "SEQUENCE")
      return 0;

    array a = asn1->elements;
    X509_WERR("TBSCertificate: sizeof(a) = %d\n", sizeof(a));
      
    if (sizeof(a) < 6)
      return 0;

    if (sizeof(a) > 6)
    {
      /* The optional version field must be present */
      if (!a[0]->constructed
	  || (a[0]->get_combined_tag() != make_combined_tag(2, 0))
	  || (sizeof(a[0]->elements) != 1)
	  || (a[0]->elements[0]->type_name != "INTEGER"))
	return 0;

      version = (int) a[0]->elements[0]->value + 1;
      if ( (version < 2) || (version > 3))
	return 0;
      a = a[1..];
    } else
      version = 1;

    X509_WERR("TBSCertificate: version = %d\n", version);
    if (a[0]->type_name != "INTEGER")
      return 0;
    serial = a[0]->value;

    X509_WERR("TBSCertificate: serial = %s\n", (string) serial);
      
    if ((a[1]->type_name != "SEQUENCE")
	|| !sizeof(a[1]->elements )
	|| (a[1]->elements[0]->type_name != "OBJECT IDENTIFIER"))
      return 0;

    algorithm = a[1];

    X509_WERR("TBSCertificate: algorithm = %s\n", algorithm->debug_string());

    if (a[2]->type_name != "SEQUENCE")
      return 0;
    issuer = a[2];

    X509_WERR("TBSCertificate: issuer = %s\n", issuer->debug_string());

    if ((a[3]->type_name != "SEQUENCE")
	|| (sizeof(a[3]->elements) != 2))
      return 0;

    array validity = a[3]->elements;

    not_before = parse_time(validity[0]);
    if (!not_before)
      return 0;
      
    X509_WERR("TBSCertificate: not_before = %O\n", not_before);

    not_after = parse_time(validity[1]);
    if (!not_after)
      return 0;

    X509_WERR("TBSCertificate: not_after = %O\n", not_after);

    if (a[4]->type_name != "SEQUENCE")
      return 0;
    subject = a[4];

    X509_WERR("TBSCertificate: keyinfo = %s\n", a[5]->debug_string());
      
    public_key = make_verifier(a[5]);

    if (!public_key)
      return 0;

    X509_WERR("TBSCertificate: parsed public key. type = %s\n",
	      public_key->type);

    int i = 6;
    if (i == sizeof(a))
      return this_object();

    if (version < 2)
      return 0;

    if (! a[i]->constructed
	&& (a[i]->combined_tag == make_combined_tag(2, 1)))
    {
      issuer_id = BitString()->decode_primitive(a[i]->raw);
      i++;
      if (i == sizeof(a))
	return this_object();
    }
    if (! a[i]->constructed
	&& (a[i]->combined_tag == make_combined_tag(2, 2)))
    {
      subject_id = BitString()->decode_primitive(a[i]->raw);
      i++;
      if (i == sizeof(a))
	return this_object();
    }
    if (a[i]->constructed
	&& (a[i]->combined_tag == make_combined_tag(2, 3)))
    {
      extensions = a[i];
      i++;
      if (i == sizeof(a))
	return this_object();
    }
    /* Too many fields */
    return 0;
  }
}

//!
TBSCertificate decode_certificate(string|object cert)
{
  if (stringp (cert)) cert = Standards.ASN1.Decode.simple_der_decode(cert);

  if (!cert
      || (cert->type_name != "SEQUENCE")
      || (sizeof(cert->elements) != 3)
      || (cert->elements[0]->type_name != "SEQUENCE")
      || (cert->elements[1]->type_name != "SEQUENCE")
      || (!sizeof(cert->elements[1]->elements))
      || (cert->elements[1]->elements[0]->type_name != "OBJECT IDENTIFIER")
      || (cert->elements[2]->type_name != "BIT STRING")
      || cert->elements[2]->unused)
    return 0;

  TBSCertificate tbs = TBSCertificate()->init(cert->elements[0]);

  if (!tbs || (cert->elements[1]->get_der() != tbs->algorithm->get_der()))
    return 0;

  return tbs;
}

//! Decodes a certificate, checks the signature. Returns the
//! TBSCertificate structure, or 0 if decoding or verification failes.
//!
//! Authorities is a mapping from (DER-encoded) names to a verifiers.
//!
//! @note
//!   This function allows self-signed certificates, and it doesn't
//!   check that names or extensions make sense.
TBSCertificate verify_certificate(string s, mapping authorities)
{
  object cert = Standards.ASN1.Decode.simple_der_decode(s);

  TBSCertificate tbs = decode_certificate(cert);
  if (!tbs) return 0;

  object v;
  
  if (tbs->issuer->get_der() == tbs->subject->get_der())
  {
    /* A self signed certificate */
    X509_WERR("Self signed certificate\n");
    v = tbs->public_key;
  }
  else
    v = authorities[tbs->issuer->get_der()];

  return v && v->verify(cert->elements[1],
			cert->elements[0]->get_der(),
			cert->elements[2]->value)
    && tbs;
}

//! Decodes a certificate chain, checks the signatures. Returns a mapping
//! with the following contents, depending on the verification of the
//! certificate chain:
//!
//! @mapping
//!   @member int(0..1) "self_signed"
//!     Non-zero if the certificate is self-signed.
//!   @member int(0..1) "verified"
//!     Non-zero if the certificate is verified.
//!   @member string "authority"
//!     DER-encoded name of the authority that verified the chain.
//! @endmapping
//!
//! @param authorities
//!   A mapping from (DER-encoded) names to verifiers.
mapping verify_certificate_chain(array(string) cert_chain, mapping authorities)
{
  mapping m = ([ ]);

  for(int i=0; i<sizeof(cert_chain); i++)
  {
    object cert = Standards.ASN1.Decode.simple_der_decode(cert_chain[i]);

    object(TBSCertificate) tbs = decode_certificate(cert);
    if (!tbs) return m;

    object v;

    if(i == sizeof(cert_chain)-1) // Last cert
      v = authorities[tbs->issuer->get_der()];
    if (!v && tbs->issuer->get_der() == tbs->subject->get_der())
    {
      /* A self signed certificate */
      m->self_signed = 1;
      X509_WERR("Self signed certificate\n");
      v = tbs->public_key;
    }
    else
      v = authorities[tbs->issuer->get_der()];

    if (v && v->verify(cert->elements[1],
		       cert->elements[0]->get_der(),
		       cert->elements[2]->value)
	&& tbs)
    {
      m->authority = tbs->issuer->get_der();
      if(v == authorities[tbs->issuer->get_der()])
	m->verified = 1;
    }
  }
  return m;
}

#endif
