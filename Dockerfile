FROM fedora:28 as base

LABEL authors = "Alex Kotlar <akotlar@emory.edu>, Jacob Meigs <jmeigs@emory.edu>" \
      version = "1.0.0"

ENV PATH="/root/mpd-perl/bin:${PATH}" \
    PERL5LIB="/root/perl5/lib/perl5:/root/mpd-perl/lib:${PERL5LIB}"

WORKDIR /root

RUN dnf install -y \
    gcc \
    gcc-c++ \
    libpng-devel \
    libuuid-devel \
    make \
    mariadb-devel \
    patch \
    perl \
    rsync \
    unzip \
    wget \
    which \
    git \
    openssh-clients \
    cpanminus

# MPD Perl
ADD ./cpanfile /root/mpd-perl/cpanfile

RUN mkdir -p /root/perl5/lib/perl \
    && cpanm --local-lib=/root/perl5 local::lib \
    && cd /root/mpd-perl \
    && eval $(perl -I /root/perl5/lib/perl5 -Mlocal::lib) \
    && cpanm --installdeps .

# MPD C
RUN git clone https://github.com/wingolab-org/mpd-c  /root/mpd-c \
    && cd /root/mpd-c && make

ADD ./ /root/mpd-perl/

FROM base as staticDeps

RUN git clone https://bitbucket.org/wingolab/mpd-dat

FROM staticDeps as isPCR

# isPCR
RUN wget http://hgdownload.cse.ucsc.edu/admin/jksrc.v371.zip \
    && unzip -q jksrc.v371.zip \
    && rm jksrc.v371.zip

RUN mkdir -p bin/x86_64 \
    && export MACHTYPE=x86_64 \
    && cd kent/src/ && make libs \
    && cd lib/ && make \
    && cd ../jkOwnLib/ && make \
    && cd ../isPcr/ && make \
    && cd /root

RUN mkdir /root/2bit && cd $_ \ 
    && wget http://hgdownload.cse.ucsc.edu/goldenPath/hg38/bigZips/hg38.2bit \
    && cd /root