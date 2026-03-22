ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# This file is the compatibility point for the old umu-sdk workflow.
# Put RUN/COPY/ENV directives here the way you used to customize
# a downloaded image, except BASE_IMAGE now points at a locally assembled
# sniper base image.
#
# Example:
# COPY docker/overlay-rootfs/ /
# RUN mkdir -p /usr/local/share/umu

CMD ["/bin/bash"]
