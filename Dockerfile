# Stage 1: Base image for development and dependencies
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04 AS base

ENV REFRESHED_AT=2024-08-12 \
    DISPLAY=:1 \
    VNC_PORT=5901 \
    NO_VNC_PORT=6901 \
    HOME=/workspace \
    TERM=xterm \
    STARTUPDIR=/dockerstartup \
    INST_SCRIPTS=/workspace/install \
    NO_VNC_HOME=/workspace/noVNC \
    DEBIAN_FRONTEND=noninteractive \
    VNC_COL_DEPTH=24 \
    VNC_PW=vncpassword \
    VNC_VIEW_ONLY=false \
    TZ=Asia/Seoul

LABEL io.k8s.description="Headless VNC Container with Xfce window manager, Firefox, and Chromium" \
      io.k8s.display-name="Headless VNC Container based on Debian" \
      io.openshift.expose-services="6901:http,5901:xvnc" \
      io.openshift.tags="vnc, debian, xfce" \
      io.openshift.non-scalable=true

WORKDIR $HOME

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      wget git build-essential software-properties-common \
      apt-transport-https ca-certificates unzip ffmpeg jq tzdata && \
    ln -fs /usr/share/zoneinfo/$TZ /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install Miniconda
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh && \
    bash miniconda.sh -b -p /opt/conda && \
    rm miniconda.sh

ENV PATH=/opt/conda/bin:$PATH

# Copy installation scripts
COPY ./src/common/install/ $INST_SCRIPTS/
COPY ./src/debian/install/ $INST_SCRIPTS/
COPY ./src/common/xfce/ $HOME/
COPY ./src/common/scripts/ $STARTUPDIR/
RUN chmod +x $INST_SCRIPTS/*.sh

# Install software and dependencies
RUN $INST_SCRIPTS/tools.sh && \
    $INST_SCRIPTS/install_custom_fonts.sh && \
    $INST_SCRIPTS/tigervnc.sh && \
    $INST_SCRIPTS/no_vnc_1.5.0.sh && \
    $INST_SCRIPTS/firefox.sh && \
    $INST_SCRIPTS/xfce_ui.sh

RUN $INST_SCRIPTS/libnss_wrapper.sh && \
    $INST_SCRIPTS/set_user_permission.sh $STARTUPDIR $HOME

# Stage 2: Build environment for Python and VisoMaster
FROM base AS build

RUN conda install -n base -c conda-forge mamba -y && \
    mamba create -n VisoMaster python=3.10.13 -y && mamba clean --all -y && \
    echo "source activate VisoMaster" >> ~/.bashrc

ENV CONDA_DEFAULT_ENV=VisoMaster
ENV PATH=/opt/conda/envs/$CONDA_DEFAULT_ENV/bin:$PATH

# Install Python packages and CUDA dependencies
RUN mamba install -n VisoMaster scikit-image -y && \
    mamba install -n VisoMaster -c nvidia/label/cuda-12.4.1 cuda-runtime cudnn -y && \
    mamba clean --all -y

# Clone and set up VisoMaster
WORKDIR /workspace
RUN git clone https://github.com/remphan1618/VisoMaster.git VisoMaster

WORKDIR /workspace/VisoMaster
RUN pip install -r requirements.txt

# Download models
WORKDIR /workspace/VisoMaster/model_assets
RUN python download_models.py

# Add the notebook
COPY VisoMaster_Setup_Fix_Simplified.ipynb /workspace/VisoMaster/

# Stage 3: Final runtime image
FROM base AS runtime

# Copy the necessary files from the build environment
COPY --from=build /workspace /workspace
COPY --from=build /opt/conda /opt/conda

WORKDIR /workspace/VisoMaster

# Create logs folder and symlink .log files
RUN mkdir -p /workspace/VisoMaster/logs && \
    find / -name "*.log" -exec ln -sf {} /workspace/VisoMaster/logs/ \;

# Reconfigure startup script
COPY ./src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh
RUN chmod 765 /dockerstartup/vnc_startup.sh

ENV VNC_RESOLUTION=1280x1024

ENTRYPOINT ["/dockerstartup/vnc_startup.sh"]
CMD ["--wait"]
