# **Discourse Media Watermark** Plugin

### **Summary**
A customized discourse plugin to add watermark to the videos and images that are uploaded in discourse forum.

### **Prerequisites**
- FFmpeg should be installed on your machine in order for video watermarking to work. 
- To check if the FFmpeg is installed in your system do the following -

1. **Production** (Docker instance)
    ```bash
    cd /var/discourse

    docker exec -it app bash        # enter docker instance

    which ffmpeg        # this should give /usr/bin/ffmpeg

    ffmpeg -version     # this will give something like this -> ffmpeg version 5.1.7-0+deb12u1 Copyright (c) 2000-2025 the FFmpeg developers
    ```

    - If you don't see the above two outputs it means ffmpeg libraries are not installed and video watermarking will not work. To fix this do the following in the following order.

    ```bash
    apt-get update or apt update        # efreshes the local list of available software packages

    apt-get upgrade or apt upgrade      # upgrades all currently installed packages on a Debian-based Linux system to their most recent versions

    apt-get install ffmpeg      # this will install the ffmpeg libraries
    ```


### **Usage**

1. **Production (Docker instance)**
- Add the following line to the app.yml in the plugin hooks.

    > The **app.yml** is available in the ```/var/discourse/containers```.

    ```bash
    hooks:
    after_code:
        - exec:
            cd: $home/plugins
            cmd:
            - git clone https://github.com/Shaurya-Jha/discourse-media-watermark.git
    ```
- Save the changes made in the app.yml file.
- Rebuild the image.
    > cd ```/var/discourse``` and run the following command.
    ```bash
    ./launcher rebuild app
    ```

2. **Development**
- To use the plugin in the development environment copy the plugin into the ```discourse/plugins``` folder.
    ```bash
    git clone https://github.com/Shaurya-Jha/discourse-media-watermark.git /plugins
    ```
- Shutdown the development docker image running.
    ```bash
    d/shutdown_dev
    ```
- Boot the development image again.
    ```bash
    d/boot_dev
    ```
    
    > Doing the shutdown and booting the image is necessary as whenever we add a new plugin we need to restart the project so that our plugin loads in our project.

- Start the server
    ```bash
    d/rails s
    d/ember-cli         # in another terminal
    ```

3. **Discourse Media Watermark**
- Go into the ```Admin``` and under the ```Plugins``` go in the ```Installed plugins``` tab. Locate or search for **Discourse Media Watermark** plugin and toggle it to on.