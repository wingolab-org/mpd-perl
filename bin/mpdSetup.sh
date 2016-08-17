#!/usr/bin/sh

git clone git@github.com:wingolab-org/mpd-c.git
cd mpd-c
make
cd ~/bin
sudo ln -sv ~/mpd-c/bin/* .

# get isPcr from UCSC / Jim Kent
sudo yum install mysql-devel libpng-devel libstdc++-devel zlib-devel
export MACHTYPE=x86_64
git clone git://genome-source.cse.ucsc.edu/kent.git

# NOTE:
# 1) Here is what you need to change in the make /src/inc/common.mk
# to enable building on AMS.
# [ec2-user@ip-172-31-55-133 kent]$ git diff
# diff --git a/src/inc/common.mk b/src/inc/common.mk
# index 1204208..e2416eb 100644
# --- a/src/inc/common.mk
# +++ b/src/inc/common.mk
# @@ -25,7 +25,7 @@ UNAME_S := $(shell uname -s)
#  FULLWARN = $(shell uname -n)
#  
#  #global external libraries 
# -L=$(kentSrc)/htslib/libhts.a
# +L=$(kentSrc)/htslib/libhts.a -lz
#  
#  # pthreads is required
#  ifneq ($(UNAME_S),Darwin)
# 2) binaries are installed to: /home/ec2-user/kent/src/lib/x86_64/

cd jkOwnLib
make
cd ..
make blatSuite


