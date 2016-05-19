COMPONENT=CMCServerExC
# uncomment this for network programming support
# BOOTLOADER=tosboot

PFLAGS += -DNEW_PRINTF_SEMANTICS

# for the printf
CFLAGS += -I$(TOSDIR)/lib/printf
CFLAGS += -DPRINTF_BUFFER_SIZE=256

# Enable debug output
CFLAGS += -DDEBUG_OUT

#enable ecc testvalues and ecc160
PFLAGS += ../../CMC/tinypkc/integer.c
CFLAGS += -DECC160

CFLAGS += -DMP_16BIT # set size of integer to 16 bit
# note: this is machine dependent and now set for AVR

CFLAGS += -DECC_TEST_VALUES # hardcoded test values in use for now
CFLAGS += -DMP_PREC=40 # precision for the large interger packet
CFLAGS += -DHAVE_ECC


# Include the CMC folder
CFLAGS += -I../../CMC
CFLAGS += -I../../CMC/tinypkc

include $(MAKERULES)

