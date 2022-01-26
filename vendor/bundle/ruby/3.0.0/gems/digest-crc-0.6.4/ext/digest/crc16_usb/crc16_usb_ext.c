#include <ruby.h>
#include "../compat/ruby.h"

#include "extconf.h"
#include "crc16_usb.h"

VALUE Digest_CRC16USB_update(VALUE self, VALUE data)
{
	VALUE crc_ivar_name = rb_intern("@crc");
	VALUE crc_ivar = rb_ivar_get(self, crc_ivar_name);
	crc16_t crc = NUM2USHORT(crc_ivar);

	const char *data_ptr = StringValuePtr(data);
	size_t length = RSTRING_LEN(data);

	crc = crc16_usb_update(crc,data_ptr,length);

	rb_ivar_set(self, crc_ivar_name, USHORT2NUM(crc));
	return self;
}

void Init_crc16_usb_ext()
{
	VALUE mDigest = rb_const_get(rb_cObject, rb_intern("Digest"));
	VALUE cCRC16USB = rb_const_get(mDigest, rb_intern("CRC16USB"));

	rb_undef_method(cCRC16USB, "update");
	rb_define_method(cCRC16USB, "update", Digest_CRC16USB_update, 1);
}
