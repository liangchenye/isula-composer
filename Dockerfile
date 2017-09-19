FROM rnd-dockerhub.huawei.com/euleros/euleros:2.0.SP2-20161201

ADD isula.repo /etc/yum.repos.d/

RUN yum update -y && yum install -y \
    ostree lorax make git golang 

ADD make-isula-image.sh /srv

USER root
CMD /bin/sh /srv/make-isula-image.sh

LABEL tag "rnd-dockerhub.huawei.com/euleros/isula-composer:V100R001C00B001"
