# **Discourse Media Watermark** Plugin

#### Summary
A customized discourse plugin to add watermark to the videos and images that are uploaded in discourse forum.

#### Usage

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