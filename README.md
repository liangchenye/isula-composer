# buildscripts

This project contains metadata and build scripts for the EulerOS iSula Host
Images.

### Maintaining the RPMs

Owner: `mailto: <liangchenye@gmail.com>`

The RPM packages are maintained in euleros rpmpkg repositories.  

### The build process

To trigger a new build, run:

  $ sudo ./build_iso.sh

This will generate a installable ISO image finally. 

The build process works like this:
At the beginning, it setup the build environment, basically install ostree, rpm-ostree and lorax tools.
Afterwards, rpm-ostree is triggered to compose a new filesystem ostree repo based on the configuration in euleros-isula-host.json,
for the detail meaning of the parameters in this json file, please refer to https://rpm-ostree.readthedocs.io/en/latest/manual/treefile,
at the end of this rpm-ostree compose stage, it will execute treecompose-post.sh scripts, so if you have any need to customize the
composed filesystem, you can add your customization in this script. Finally lorax script is used to generate a installable ISO image
based on the previously composed ostree repo.

Instead of storing ostree repo locally, you can also set up a ostree server to keep the history of filesystem ostree repo remotely.

### Contributing

Feel free to send pull request to contribute to this project.
