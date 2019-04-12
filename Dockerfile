# Based on Jeremiah H. Savage <jeremiahsavage@gmail.com> 's kent image
FROM fedora:28

MAINTAINER Alex Kotlar <akotlar@emory.edu>

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
    openssh-clients

RUN wget http://hgdownload.cse.ucsc.edu/admin/jksrc.v371.zip \
    && unzip -q jksrc.v371.zip \
    && rm jksrc.v371.zip

RUN mkdir -p bin/x86_64 \
    && export MACHTYPE=x86_64 \
    && cd kent/src/ && make libs \
    && cd lib/ && make \
    && cd ../jkOwnLib/ && make \
    && cd ../isPcr/ && make \
    && cd /root && rm -rf kent

WORKDIR /root

RUN git clone https://bitbucket.org/wingolab/mpd-dat \
    && mkdir /root/2bit && cd $_ \ 
    && wget http://hgdownload.cse.ucsc.edu/goldenPath/hg38/bigZips/hg38.2bit \
    && cd /root

WORKDIR /root

ADD ./ /root/mpd-perl/

RUN curl -L https://cpanmin.us | perl - App::cpanminus \
    && mkdir -p /root/perl5/lib/perl \
    && cpanm --local-lib=/root/perl5 local::lib && eval $(perl -I /root/perl5/lib/perl5 -Mlocal::lib) \
    && cd /root/mpd-perl && cpanm MPD.tar.gz && cpanm --installdeps . \
    && git clone https://github.com/wingolab-org/mpd-c /root/mpd-c \
    && cd /root/mpd-c && make

WORKDIR /root/mpd-perl/
