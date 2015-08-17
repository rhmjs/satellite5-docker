# Building RHEL6 docker containers on RHEL7 hosts registered to Satellite 5
This document will describe the process for building containers including RHEL6 on a RHEL7 host the is registered to Satellite 5.

## Environment
* Satellite 5.7
* RHEL 7.1 host for buidling containers, registered to Satellite via rhn_register

## Preparing Satellite
The RHEL7 host needs access to a small number of RHEL6 packages (RHN client utilities) to inject into the RHEL6 image.  To make these packages available, a child channel will be created under the RHEL7 base channel.

The spacecmd utility can be used to create this channel structure, and to create an activation key that can be used to associate the container with the RHEL6 channel(s).
```
# Login with admin credentials
spacecmd login 

# Create a new channel named "rhel7-rhel6-rhn" as child to the RHEL7 base channel
spacecmd softwarechannel_create -n rhel7-rhel6-rhn -l rhel7-rhel6-rhn -p rhel-x86_64-server-7 -a x86_64

# Copy necessary packages from RHEL6 to this new channel
spacecmd softwarechannel_addpackages rhel7-rhel6-rhn rhn-setup-1*.el6.noarch libgudev1*.el6.x86_64 libudev*.el6.x86_64 newt*.el6.x86_64 newt-python*.el6.x86_64 pyOpenSSL*.el6.x86_64 python-gudev*.el6.x86_64 rhn-check*.el6.noarch rhn-client-tools*.el6.noarch rhnlib*.el6.noarch rhnsd*.el6.x86_64 slang*.el6.x86_64 yum-rhn-plugin*.el6.noarch

# Create an activation key associated with the rhel6 channel, granting a single usage
spacecmd activationkey_create -n rhel7-docker-rhel6 -b rhel-x86_64-server-6
spacecmd activationkey_setusagelimit 1-rhel7-docker-rhel6 1
```

## Preparing the RHEL7 docker build server
Prepare the RHEL7 docker build server by running the following commands:
```
# Subscribe to the new rhel6 child channel
rhn-channel -a -c rhel7-rhel6-rhn

# Download the necessary RPMs
yumdownloader --destdir=$PWD/rhel6/ --disablerepo=*  --enablerepo=rhel7-rhel6-rhn rhn-setup libgudev1 libudev newt newt-python pyOpenSSL python-gudev rhn-check rhn-client-tools rhnlib rhnsd slang yum-rhn-plugin
```

## Creating the RHN connected rhel6 image

Create the following dockerfile, named Dockerfile.rhel6-rhn, on the RHEL7 docker build server.
```
FROM registry.access.redhat.com/rhel6

ADD rhel6/*.rpm /root/rhel6/
ADD http://satellite5-1.laptop.test/pub/rhn-org-trusted-ssl-cert-1.0-1.noarch.rpm /root/rhel6/

RUN yum localinstall -y /root/rhel6/*.rpm
#ADD systemid /etc/sysconfig/rhn/
#ADD up2date /etc/sysconfig/rhn/
RUN sed -i 's/^enabled *= *0$/enabled = 1/' /etc/yum/pluginconf.d/rhnplugin.conf

RUN sed -i '82s/$/ if device else None/' /usr/share/rhn/up2date_client/hwdata.py

CMD if [ ! -e /etc/sysconfig/rhn/systemid ]; then rhnreg_ks --force --norhnsd --nohardware --nopackages --serverUrl=https://satellite5-1.laptop.test/XMLRPC --sslCACert=/usr/share/rhn/RHN-ORG-TRUSTED-SSL-CERT --profilename=docker-rhel6 --activationkey=1-rhel7-docker-rhel6; fi
```

Build the image.
```
docker build -t rhel6-rhn -f Dockerfile.rhel6-rhn  .
```

Execute the image to register and create a profile in Satellite 5.  Note that using '--privileged' allows the registration to determine if the container host is a VM.  Then, commit the registration to the rhel6-rhn-reg image
```
docker run --privileged --name="rhel6-rhn-reg" rhel6-rhn
docker commit rhel6-rhn-reg rhel6-rhn-reg
```

Base image named 'rhel6-rhn-reg' is now created.

## Create an application image

This example will create an Apache web server on top of the rhel6-rhn-reg image created in previous section.

Create the following dockerfile named "Dockerfile.rhel6-httpd"
```
FROM rhel6-rhn-reg
RUN yum -y install httpd systemd
EXPOSE 80
ENTRYPOINT /usr/sbin/httpd -X
```

Build the rhel6-httpd image.
```
docker build -t rhel6-httpd -f Dockerfile.rhel6-httpd .
```

Execute the rhel6-httpd image.
```
docker run rhel6-httpd
```
