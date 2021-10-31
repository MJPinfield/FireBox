# Build easy-vnc
FROM golang:1.14-buster AS easy-novnc-build
WORKDIR /src
RUN go mod init build && \
    go get github.com/geek1011/easy-novnc@v1.1.0 && \
    go build -o /bin/easy-novnc github.com/geek1011/easy-novnc

# Build the application
# Download the requirements
FROM debian:bullseye
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        tigervnc-standalone-server \
        supervisor \
        openbox \
        gosu && \
    rm -rf /var/lib/apt/lists && \
    mkdir -p /usr/share/desktop-directories
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        software-properties-common \
        rsync ca-certificates \
        openssh-client \
        libnss3-tools \
        lxterminal \
        xdg-utils \
        python3 \
        bzip2 \
        gnupg \
        unzip \
        nano \
        wget \
        htop \
        xzip \
        gzip \
        tar \
        zip \
        git && \
    rm -rf /var/lib/apt/lists

# Install chrome
RUN wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get update -y && \
    apt-get install -y \
        --no-install-recommends ./google-chrome-stable_current_amd64.deb && \
    rm -rf /var/lib/apt/lists

# Download MITM Proxy
RUN wget -q https://snapshots.mitmproxy.org/7.0.4/mitmproxy-7.0.4-linux.tar.gz && \
    mkdir -p /opt/mitmproxy && \
    tar -zxf mitmproxy-7.0.4-linux.tar.gz --directory /opt/mitmproxy && \
    rm mitmproxy-7.0.4-linux.tar.gz

# Configure the application
COPY --from=easy-novnc-build /bin/easy-novnc /usr/local/bin/
COPY menu.xml /etc/xdg/openbox/
COPY supervisord.conf /etc/
COPY policies.json /usr/lib/firefox/distribution/
COPY root-csr.conf /opt/mitmproxy/

# Create the root CA
RUN openssl req \
        -x509 \
        -sha256 \
        -days 3650 \
        -newkey rsa:3072 \
        -config /opt/mitmproxy/root-csr.conf \
        -out /opt/mitmproxy/acme.crt \
        -keyout /opt/mitmproxy/acme.key && \
    cat /opt/mitmproxy/acme.key /opt/mitmproxy/acme.crt > /opt/mitmproxy/mitmproxy-ca.pem && \
    mkdir -p $HOME/.pki/nssdb && \
    certutil -d $HOME/.pki/nssdb -N && \
    certutil -d sql:$HOME/.pki/nssdb -A -t "C,," \
        -n "ACME Corp Root CA" \
        -i /opt/mitmproxy/mitmproxy-ca.pem
        

RUN groupadd --gid 1000 app && \
    useradd --home-dir /data \
        --shell /bin/bash \
        --uid 1000 \
        --gid 1000 app && \
    mkdir -p /data && \
    mkdir /data/downloads && \
    chown -R app:app /data /opt/mitmproxy

EXPOSE 8080
CMD ["sh", "-c", "chown app:app /data /dev/stdout && exec gosu app supervisord"]