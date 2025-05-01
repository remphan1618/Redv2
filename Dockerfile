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
ADD ./src/common/install/ $INST_SCRIPTS/
ADD ./src/debian/install/ $INST_SCRIPTS/

### Give executable permissions to all the scripts in $INST_SCRIPTS
RUN chmod +x $INST_SCRIPTS/*.sh

### Install some common tools
RUN $INST_SCRIPTS/tools.sh
ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8'

### Install custom fonts
RUN $INST_SCRIPTS/install_custom_fonts.sh

### Install xvnc-server & noVNC - HTML5 based VNC viewer
RUN $INST_SCRIPTS/tigervnc.sh
RUN $INST_SCRIPTS/no_vnc_1.5.0.sh

### Install firefox and chrome browser
RUN $INST_SCRIPTS/firefox.sh

### Install xfce UI
RUN $INST_SCRIPTS/xfce_ui.sh
ADD ./src/common/xfce/ $HOME/

### Configure startup
RUN $INST_SCRIPTS/libnss_wrapper.sh
ADD ./src/common/scripts $STARTUPDIR
RUN $INST_SCRIPTS/set_user_permission.sh $STARTUPDIR $HOME

### Create conda environment
RUN conda create -n visomaster python=3.10.13 && conda clean --all -y

### Activate the environment
ENV CONDA_DEFAULT_ENV visomaster
RUN echo "source activate $CONDA_DEFAULT_ENV" >> ~/.bashrc
ENV PATH /opt/conda/envs/$CONDA_DEFAULT_ENV/bin:$PATH

### Install CUDA and cuDNN
RUN conda install -c nvidia/label/cuda-12.4.1 cuda-runtime
RUN conda install -c conda-forge cudnn

### Install visomaster
WORKDIR /workspace
RUN git clone https://github.com/visomaster/VisoMaster.git
WORKDIR /workspace/visomaster

### Install dependencies. Fix Models.py backslash path
RUN pip install -r ./requirements.txt --no-cache-dir
RUN conda install scikit-image
RUN pip install -r requirements_cu124.txt

### Download models
WORKDIR /workspace/visomaster/model_assets
RUN python download_models.py
WORKDIR /workspace/visomaster/model_assets

### Install jupyterlab
RUN pip install jupyterlab
EXPOSE 8080

### Install filebrowser
RUN wget -O - https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash
EXPOSE 8585

### Reconfigure startup
COPY ./src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh
RUN chmod 765 /dockerstartup/vnc_startup.sh

ENV VNC_RESOLUTION=1280x1024

ENTRYPOINT ["/dockerstartup/vnc_startup.sh"]
CMD ["--wait"]
