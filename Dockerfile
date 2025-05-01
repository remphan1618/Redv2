# Use NVIDIA CUDA base image
FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

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

LABEL io.k8s.description="Headless VNC Container with Xfce window manager, firefox and chromium" \
      io.k8s.display-name="Headless VNC Container based on Debian" \
      io.openshift.expose-services="6901:http,5901:xvnc" \
      io.openshift.tags="vnc, debian, xfce" \
      io.openshift.non-scalable=true

# Expose relevant ports
EXPOSE $VNC_PORT $NO_VNC_PORT

WORKDIR $HOME

# Update, install dependencies, set up timezone, and clean up in one layer.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      wget \
      git \
      build-essential \
      software-properties-common \
      apt-transport-https \
      ca-certificates \
      unzip \
      ffmpeg \
      jq \
      tzdata && \
    ln -fs /usr/share/zoneinfo/$TZ /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata && \
    rm -rf /var/lib/apt/lists/*

# Install Miniconda
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh && \
    bash miniconda.sh -b -p /opt/conda && \
    rm miniconda.sh

# Add Conda to the PATH
ENV PATH=/opt/conda/bin:$PATH

# Copy installation scripts
COPY ./src/common/install/ $INST_SCRIPTS/
COPY ./src/debian/install/ $INST_SCRIPTS/
COPY ./src/common/xfce/ $HOME/
COPY ./src/common/scripts/ $STARTUPDIR/

# Make all install scripts executable
RUN chmod +x $INST_SCRIPTS/*.sh

# Diagnose: List the contents of $STARTUPDIR to confirm scripts copied correctly.
RUN ls -la $STARTUPDIR

# Install common tools, custom fonts, VNC, browsers, and XFCE UI in one layer if possible
RUN $INST_SCRIPTS/tools.sh && \
    $INST_SCRIPTS/install_custom_fonts.sh && \
    $INST_SCRIPTS/tigervnc.sh && \
    $INST_SCRIPTS/no_vnc_1.5.0.sh && \
    $INST_SCRIPTS/firefox.sh && \
    $INST_SCRIPTS/xfce_ui.sh

# Configure startup: wrap user permission changes and library configuration
RUN $INST_SCRIPTS/libnss_wrapper.sh && \
    $INST_SCRIPTS/set_user_permission.sh $STARTUPDIR $HOME

# Create and configure the Conda environment in one shot to reduce layers.
RUN conda create -n visomaster python=3.10.13 -y && conda clean --all -y && \
    echo "source activate visomaster" >> ~/.bashrc

ENV CONDA_DEFAULT_ENV=visomaster
ENV PATH=/opt/conda/envs/$CONDA_DEFAULT_ENV/bin:$PATH

# Install additional Python packages and CUDA dependencies
RUN conda install scikit-image -y && \
    conda install -c nvidia/label/cuda-12.4.1 cuda-runtime -y && \
    conda install -c conda-forge cudnn -y && \
    conda clean --all -y

# Clone and install VisoMaster
WORKDIR /workspace
RUN git clone https://github.com/remphan1618/VisoMaster && \
    cd VisoMaster && \
    echo "VisoMaster cloned"

# Install dependencies
WORKDIR /workspace/visomaster
RUN conda install scikit-image -y
RUN pip install -r requirements_cu124.txt

# Download models
WORKDIR /workspace/visomaster/model_assets
RUN python download_models.py

# Add the notebook into the VisoMaster directory
COPY VisoMaster_Setup_Fix_Simplified.ipynb /workspace/visomaster/

# Create logs folder and symlink .log files
RUN mkdir -p /workspace/visomaster/logs && \
    find / -name "*.log" -exec ln -sf {} /workspace/visomaster/logs/ \;

# Reconfigure startup script
COPY ./src/vnc_startup_jupyterlab_filebrowser.sh /dockerstartup/vnc_startup.sh
RUN chmod 765 /dockerstartup/vnc_startup.sh

ENV VNC_RESOLUTION=1280x1024

ENTRYPOINT ["/dockerstartup/vnc_startup.sh"]
CMD ["--wait"]
