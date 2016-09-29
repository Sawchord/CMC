COMPONENT=CMCExC
# uncomment this for network programming support
# BOOTLOADER=tosboot

PFLAGS += -DNEW_PRINTF_SEMANTICS

# for the printf
CFLAGS += -I$(TOSDIR)/lib/printf
CFLAGS += -DPRINTF_BUFFER_SIZE=1024

CFLAGS += -I$/../../CMC/TinyECC
CFLAGS += -I$/../../CMC/crypto

# Enable debug output
CFLAGS += -DDEBUG_OUT
#CFLAGS += -DBENCHMARK

# Enable AES128 encryption
CFLAGS += -DUSE_AES128

##choose curve parameter
#CFLAGS+=-DSECP128R1
#CFLAGS+=-DSECP128R2
#CFLAGS+=-DSECP160K1
CFLAGS+=-DSECP160R1
#CFLAGS+=-DSECP160R2
#CFLAGS+=-DSECP192K1
#CFLAGS+=-DSECP192R1


#use test vector for secp160r1 to show the correctness of TinyECC
#CFLAGS += -DTEST_VECTOR 
#CFLAGS += -DEIGHT_BIT_PROCESSOR
#CFLAGS+=-DCODE_SIZE

##choose different optimization techniques
##NN
#CFLAGS+=-DBARRETT_REDUCTION  #barrett reduction
CFLAGS+=-DHYBRID_MULT  #hybrid multipliation
CFLAGS+=-DHYBRID_SQR  #hybrid squre
CFLAGS+=-DCURVE_OPT  #optimization for secg curve
##ECC
CFLAGS+=-DPROJECTIVE  #projective coordinate
CFLAGS+=-DSLIDING_WIN  #sliding window method, window size is defined in ECC.h
##ECDSA
CFLAGS+=-DSHAMIR_TRICK  #shamir trick, windows size is defined in ECDSAM.nc

# CFLAGS+=-DCMC_CLIENT_ONLY

CFLAGS += -DTOSH_DATA_LENGTH=100

# Include the CMC folder
CFLAGS += -I../../CMC
CFLAGS += -I../../CMC/tinypkc

include $(MAKERULES)

