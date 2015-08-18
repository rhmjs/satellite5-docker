# RHEL6 containers on a RHEL7 host registered to Satellite 5

This document will describe the process for building RHEL6 containers on
a RHEL7 host that is registered to Satellite 5.  The process will create
a base RHEL6 image that is registered to Satellite, and application
containers can be built on top of this base.

## Environment
* Satellite 5.7
* RHEL 7.1 host for buidling containers, registered to Satellite

## Preparing Satellite
The RHEL7 host needs access to a small number of RHEL6 packages
(RHN client utilities) to inject into the RHEL6 image.

The following steps must be performed by the Satellite Administrator,
from the Satellite GUI, or using the supplied CLI examples on the
Satellite server.

**Note: these steps assume your RHEL7 container host is subscribed to
the "rhel-x86_64-server-7" base channel, and your RHEL6 container will
be subscribed to the "rhel-x86_64-server-6" channel.  Please adjust
if you are subscribing to locally cloned channels.**

* Confirm that the Satellite server contains the RHEL6 and RHEL7
  base channels and RHN tools channels.

	```
	satellite-sync -c rhel-x86_64-server-6 \
	  -c rhn-tools-rhel-x86_64-server-6 \
	  -c rhel-x86_64-server-7 \
	  -c rhn-tools-rhel-x86_64-server-7
	```

* Create a channel named "rhel7-rhel6-rhn" as a child to the 
  "rhel-x86_64-server-7" base channel.
  
	```
spacecmd softwarechannel_create -n rhel7-rhel6-rhn \
  -l rhel7-rhel6-rhn -p rhel-x86_64-server-7 -a x86_64
	```

* Copy the following packages from the RHEL6 channel to this new child
  channel:
	- rhn-setup
	- libgudev1
	- libudev
	- newt
	- newt-python
	- pyOpenSSL
	- python-gudev
	- rhn-check
	- rhn-client-tools
	- rhnlib
	- rhnsd
	- slang
	- yum-rhn-plugin


	```
spacecmd softwarechannel_addpackages rhel7-rhel6-rhn \
  rhn-setup-1*.el6.noarch libgudev1*.el6.x86_64 \
  libudev*.el6.x86_64 newt*.el6.x86_64 newt-python*.el6.x86_64 \
  pyOpenSSL*.el6.x86_64 python-gudev*.el6.x86_64 \
  rhn-check*.el6.noarch rhn-client-tools*.el6.noarch \
  rhnlib*.el6.noarch rhnsd*.el6.x86_64 slang*.el6.x86_64 \
  yum-rhn-plugin*.el6.noarch
	```

Finally, an activation key must be created to allow the container to
register non-interactively.  Again, this must be performed by the 
Satellite Administrator, from the Satellite GUI, or using the supplied 
CLI examples on the Satellite server.

* Create an activation key named "rhel7-docker-rhel6" associated with
  the "rhel-x86_64-server-6" base channel, and limit its usage to "1".

	```
spacecmd activationkey_create -n rhel7-docker-rhel6 \
 -b rhel-x86_64-server-6

spacecmd activationkey_setusagelimit 1-rhel7-docker-rhel6 1
	```

## Preparing the RHEL7 docker build server
The RHEL7 container host that will be used to build containers must
now be subscribed to the child channel created above and must
download the required RHEL6 packages.  These steps must be performed
by an Administrator with root access on the RHEL7 host, via CLI on the 
RHEL7 host.

* Subscribe the RHEL7 host to the "rhel7-rhel6-rhn" child channel.

	```
rhn-channel -a -c rhel7-rhel6-rhn
	```

* Create a local working directory and switch into it.

	```
mkdir docker

cd docker
	```

* Download the RHEL6 RPMs into a subdirectory in the working folder
  named "./rhel6".

	```
yumdownloader --destdir=$PWD/rhel6/ --disablerepo=*  \
  --enablerepo=rhel7-rhel6-rhn rhn-setup libgudev1 libudev newt \
  newt-python pyOpenSSL python-gudev rhn-check rhn-client-tools \
  rhnlib rhnsd slang yum-rhn-plugin
	```

## Creating the RHN connected rhel6 image
To create layered RHEL6 images that can use "yum install" during build,
it is necessary to create a new base image that is registered to the
Satellite server.  This process will create a new RHEL6 base image
containing the RHN tools, will launch that image as a "privileged"
container so that the RHN tools can detect the underlying host to
register to the Satellite server with the correct subscription type,
then will commit that registered container to a new image that can be
used as a base for future application containers.

* Create the following dockerfile, named 
  [Dockerfile.rhel6-rhntools](Dockerfile.rhel6-rhntools), on the RHEL7 
  docker build server.

	```
	# Start with the RHEL6 base image supplied by Red Hat
	FROM registry.access.redhat.com/rhel6

	# Inject and install the RHEL6 rhn tools acquired by the host
	ADD rhel6/*.rpm /root/rhel6/
	ADD http://satellite5-1.laptop.test/pub/rhn-org-trusted-ssl-cert-1.0-1.noarch.rpm /root/rhel6/
	RUN yum localinstall -y /root/rhel6/*.rpm

	# Enable the RHN plugin
	RUN sed -i 's/^enabled *= *0$/enabled = 1/' /etc/yum/pluginconf.d/rhnplugin.conf

	# Fix up one error that occurs when rhn tools runs inside container
	RUN sed -i '82s/$/ if device else None/' /usr/share/rhn/up2date_client/hwdata.py
	```

* Build the "rhel6-rhntools" image".

	```
	docker build -t rhel6-rhntools -f Dockerfile.rhel6-rhntools  .
	```

* Execute the image to register and create a profile in Satellite 5.
  Note that using '--privileged' allows the registration to determine if
  the container host is a VM.  Then, commit the registration to the
  "rhel6-sat5reg" image.  This will create a profile named
  "docker-rhel6" in the Satellite server.

	```
	docker run --privileged --name="rhel6-sat5reg" rhel6-rhntools rhnreg_ks\
	 --force --norhnsd --nohardware --nopackages \
	 --serverUrl=https://satellite5-1.laptop.test/XMLRPC \
	 --sslCACert=/usr/share/rhn/RHN-ORG-TRUSTED-SSL-CERT \
	 --profilename=docker-rhel6 --activationkey=1-rhel7-docker-rhel6
	 
	docker commit rhel6-sat5reg rhel6-sat5reg
	```

An image named rhel6-sat5reg has now been successfully created, and can
be used as the base for future application containers.

## Example: Create a RHEL6 Apache httpd server
This example will create an Apache web server on top of the
rhel6-sat5reg image.

* Create the following dockerfile named 
  [Dockerfile.rhel6-httpd](Dockerfile.rhel6-httpd).

	```
	FROM rhel6-sat5reg
	RUN yum -y install httpd systemd
	EXPOSE 80
	ENTRYPOINT /usr/sbin/httpd -X
	```

* Build the rhel6-httpd image.

	```
	docker build -t rhel6-httpd -f Dockerfile.rhel6-httpd .
	```

* Execute the rhel6-httpd image.

	```
	docker run -p 80:5000 rhel6-httpd
	```

* Connect to the web server to confirm.

	```
	curl localhost:5000
	```

