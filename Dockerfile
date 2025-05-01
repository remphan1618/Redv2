FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

ENV REFRESHED_AT 2024-08-12

LABEL io.k8s.description="Headless VNC Container with Xfce window manager, firefox and chromium" \
      io.k8s.display-name="Headless VNC Container based on Debian" \
      io.openshift.expose-services="6901:http,5901:xvnc" \
      io.openshift.tags="vnc, debian, xfce" \
      io.openshift.non-scalable=true

### Connection ports for controlling the UI:
### VNC port:5901
### noVNC webport, connect via http://IP:6901/?password=vncpassword
ENV DISPLAY=:1 \
    VNC_PORT=5901 \
    NO_VNC_PORT=6901
EXPOSE $VNC_PORT $NO_VNC_PORT

### Envrionment config
ENV HOME=/workspace \
    TERM=xterm \
    STARTUPDIR=/dockerstartup \
    INST_SCRIPTS=/workspace/install \
    NO_VNC_HOME=/workspace/noVNC \
    DEBIAN_FRONTEND=noninteractive \
    VNC_COL_DEPTH=24 \
    VNC_PW=vncpassword \
    VNC_VIEW_ONLY=false \
    TZ=Asia/Seoul
WORKDIR $HOME

### Install necessary dependencies
RUN apt-get update && apt-get install -y \
    wget \
    git \
    build-essential \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    git \
    unzip \
    ffmpeg \
    jq \
    tzdata && \
    ln -fs /usr/share/zoneinfo/$TZ /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata && \
    rm -rf /var/lib/apt/lists/*

### Install Miniconda
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh && \
bash miniconda.sh -b -p /opt/conda && \
rm miniconda.sh

### Add Conda to the PATH
ENV PATH /opt/conda/bin:$PATH

### Add all install scripts for further steps
# Make sure the target directory exists before copying files
RUN mkdir -p $INST_SCRIPTS
ADD ./src/common/install/ $INST_SCRIPTS/
ADD ./src/debian/install/ $INST_SCRIPTS/

### Give executable permissions to all the scripts in $INST_SCRIPTS
RUN find $INST_SCRIPTS -name "*.sh" -type f -exec chmod +x {} \; || true

### Install some common tools
RUN if [ -f "$INST_SCRIPTS/tools.sh" ]; then \
        $INST_SCRIPTS/tools.sh; \
    else \
        echo "tools.sh not found, installing essential tools directly"; \
        apt-get update && apt-get install -y --no-install-recommends \
            sudo \
            vim \
            net-tools \
            locales \
            bzip2 \
            ca-certificates \
            curl \
            && apt-get clean -y \
            && rm -rf /var/lib/apt/lists/*; \
    fi
ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8'

### Install custom fonts
RUN if [ -f "$INST_SCRIPTS/install_custom_fonts.sh" ]; then \
        $INST_SCRIPTS/install_custom_fonts.sh; \
    else \
        echo "install_custom_fonts.sh not found, skipping custom font installation"; \
    fi

### Install xvnc-server & noVNC - HTML5 based VNC viewer
RUN if [ -f "$INST_SCRIPTS/tigervnc.sh" ]; then \
        $INST_SCRIPTS/tigervnc.sh; \
    else \
        echo "tigervnc.sh not found, installing TigerVNC directly"; \
        apt-get update && apt-get install -y --no-install-recommends \
            tigervnc-standalone-server \
            tigervnc-common \
            && apt-get clean -y \
            && rm -rf /var/lib/apt/lists/*; \
    fi

RUN if [ -f "$INST_SCRIPTS/no_vnc_1.5.0.sh" ]; then \
        $INST_SCRIPTS/no_vnc_1.5.0.sh; \
    else \
        echo "no_vnc_1.5.0.sh not found, installing noVNC directly"; \
        mkdir -p $NO_VNC_HOME/utils/websockify \
        && wget -qO- https://github.com/novnc/noVNC/archive/v1.5.0.tar.gz | tar xz --strip 1 -C $NO_VNC_HOME \
        && wget -qO- https://github.com/novnc/websockify/archive/v0.11.0.tar.gz | tar xz --strip 1 -C $NO_VNC_HOME/utils/websockify \
        && chmod +x -v $NO_VNC_HOME/utils/*.sh; \
    fi

### Install firefox and chrome browser
RUN if [ -f "$INST_SCRIPTS/firefox.sh" ]; then \
        $INST_SCRIPTS/firefox.sh; \
    else \
        echo "firefox.sh not found, installing Firefox directly"; \
        apt-get update && apt-get install -y --no-install-recommends \
            firefox-esr \
            && apt-get clean -y \
            && rm -rf /var/lib/apt/lists/*; \
    fi

### Install IceWM UI
RUN if [ -f "$INST_SCRIPTS/icewm_ui.sh" ]; then \
        $INST_SCRIPTS/icewm_ui.sh; \
    else \
        echo "icewm_ui.sh not found, installing IceWM directly"; \
        apt-get update && apt-get install -y --no-install-recommends \
            icewm \
            xterm \
            xfonts-base \
            xauth \
            xinit \
            x11-xserver-utils \
        && apt-get clean -y \
        && rm -rf /var/lib/apt/lists/*; \
    fi
ADD ./src/debian/icewm/ $HOME/ || true

### configure startup
RUN if [ -f "$INST_SCRIPTS/libnss_wrapper.sh" ]; then \
        $INST_SCRIPTS/libnss_wrapper.sh; \
    else \
        echo "libnss_wrapper.sh not found, skipping libnss wrapper setup"; \
    fi
ADD ./src/common/scripts $STARTUPDIR || true
RUN if [ -f "$INST_SCRIPTS/set_user_permission.sh" ]; then \
        $INST_SCRIPTS/set_user_permission.sh $STARTUPDIR $HOME; \
    else \
        echo "set_user_permission.sh not found, setting basic permissions"; \
        mkdir -p $STARTUPDIR \
        && chmod 755 $STARTUPDIR \
        && chmod 755 $HOME; \
    fi

### Create conda environment
RUN conda create -n visomaster python=3.10.13 && conda clean --all -y

### Activate the environment
ENV CONDA_DEFAULT_ENV Rope
RUN echo "source activate $CONDA_DEFAULT_ENV" >> ~/.bashrc
ENV PATH /opt/conda/envs/$CONDA_DEFAULT_ENV/bin:$PATH

### Install CUDA and cuDNN
RUN conda install -c nvidia/label/cuda-12.4.1 cuda-runtime
RUN conda install -c conda-forge cudnn

### Install visomaster
WORKDIR /workspace
RUN git clone https://github.com/remphan1618/VisoMaster
WORKDIR /workspace/visomaster
RUN mkdir -p Logs

# Copy setup notebook
COPY ./setup_visomaster.ipynb /workspace/visomaster/

### Install filebrowser
RUN wget -O - https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash
EXPOSE 8585

### Reconfigure startup
COPY ./src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh
RUN chmod 765 /dockerstartup/vnc_startup.sh

ENV VNC_RESOLUTION=1280x1024

ENTRYPOINT ["/dockerstartup/vnc_startup.sh"]
CMD ["--wait"]
