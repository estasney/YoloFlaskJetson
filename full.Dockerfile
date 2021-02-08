FROM nvcr.io/nvidia/l4t-base:r32.4.4 AS sources

WORKDIR /home

RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    build-essential \
    bzip2 \
    ca-certificates \
    netbase \
    cmake \
    dpkg-dev \
    file \
    g++ \
    gcc \
    gfortran \
    git \
    imagemagick \
    libatlas-base-dev \
    libavcodec-dev \
    libavformat-dev \
    libavresample-dev \
    libbluetooth-dev \
    libbz2-dev \
    libc6-dev \
    libcanberra-gtk3-module \
    libcurl4-openssl-dev \
    libdb-dev \
    libdc1394-22-dev \
    libeigen3-dev \
    libevent-dev \
    libffi-dev \
    libgdm-dev \
    libglew-dev \
    libglib2.0-dev \
    libgmp-dev \
    libgstreamer-plugins-base1.0-dev \
    libgstreamer-plugins-good1.0-dev \
    libgstreamer1.0-dev \
    libgtk-3-dev \
    libjpeg-dev \
	libjpeg-turbo8-dev \
	libjpeg8-dev \
	libkrb5-dev \
	liblapack-dev \
	liblapacke-dev \
	liblzma-dev \
	libmagickcore-dev \
    libmagickwand-dev \
    libmysqlclient-dev \
    libncurses5-dev \
    libncursesw5-dev \
    libopenblas-dev \
    libpng-dev \
    libpostproc-dev \
    libpq-dev \
    libreadline-dev \
    libsqlite3-dev \
    libssl-dev \
    libswscale-dev \
    libtbb-dev \
    libtbb2 \
    libtesseract-dev \
    libtiff-dev \
    libtool \
    libv4l-dev \
    libwebp-dev \
    libx264-dev \
    libxine2-dev \
    libxml2-dev \
    libxslt-dev \
    libxvidcore-dev \
    libyaml-dev \
    make \
    nano \
    patch \
    pkg-config \
    python-dev \
    qv4l2 \
    supervisor \
    unzip \
    uuid-dev \
    v4l-utils \
    v4l2ucp \
    wget \
    xz-utils \
    zlib1g-dev \
    && apt-get remove --purge --auto-remove -y \
	&& rm -rf /var/lib/apt/lists/*

RUN mkdir build_opencv \
    && cd build_opencv \
    && git clone --depth 1 --branch 4.4.0 https://github.com/opencv/opencv.git \
	&& git clone --depth 1 --branch 4.4.0 https://github.com/opencv/opencv_contrib.git

RUN wget -O nginx.tar.gz https://nginx.org/download/nginx-1.19.5.tar.gz > /dev/null 2>&1 \
    && tar -xzf nginx.tar.gz \
    && rm nginx.tar.gz

RUN wget -O python.tar.xz "https://www.python.org/ftp/python/3.8.7/Python-3.8.7.tar.xz" \
	&& mkdir -p /usr/src/python \
	&& tar -xJC /usr/src/python --strip-components=1 -f python.tar.xz \
	&& rm python.tar.xz

#===========================
FROM sources as build_python
# ensure local python is preferred over distribution python
ENV PATH /usr/local/bin:$PATH
ENV LANG C.UTF-8

RUN cd /usr/src/python \
    && ./configure \
    --with-lto \
	--enable-optimizations

RUN cd /usr/src/python \
    && make -j4 \
    && make install

RUN ln -s /usr/local/bin/pip3 /usr/bin/pip \
    && pip install --upgrade pip \
    && pip install --no-cache-dir numpy scipy scikit-build ninja PyYaml \
    && rm -rf /tmp/*


#================================
FROM build_python AS build_opencv

WORKDIR /home/build_opencv/opencv/build

RUN cmake -DBUILD_EXAMPLES=OFF -DBUILD_opencv_python2=OFF -DBUILD_opencv_python3=ON -DCMAKE_BUILD_TYPE=RELEASE \
 -DCMAKE_INSTALL_PREFIX=/usr/local -DCUDA_ARCH_BIN='5.3;6.2;7.2' -DCUDA_ARCH_PTX= -DCUDA_FAST_MATH=ON \
 -DCUDNN_VERSION='8.0' -DEIGEN_INCLUDE_PATH=/usr/include/eigen3 -DENABLE_NEON=ON -DOPENCV_DNN_CUDA=ON \
 -DOPENCV_ENABLE_NONFREE=ON -DOPENCV_EXTRA_MODULES_PATH=/home/build_opencv/opencv_contrib/modules \
 -DOPENCV_GENERATE_PKGCONFIG=ON -DWITH_CUBLAS=ON -DWITH_CUDA=ON -DWITH_CUDNN=ON -DWITH_GSTREAMER=ON \
 -DWITH_LIBV4L=ON -DWITH_OPENGL=ON -DPYTHON3_EXECUTABLE=$(which python3) -DPYTHON3_INCLUDE_DIR='/usr/local/include/python3.8' \
 -DPYTHON3_PACKAGES_PATH="/usr/local/lib/python3.8/site-packages" .. 2>&1 | tee -a configure.log

RUN make -j4 2>&1 | tee -a build.log
RUN make install 2>&1 | tee -a install.log

WORKDIR /home


#=============================
FROM build_opencv as build_torch

# https://gist.github.com/dusty-nv/ce51796085178e1f38e3c6a1663a93a1#file-pytorch-1-7-jetpack-4-4-1-patch
COPY /ops/patches/pytorch-1.7-jetpack-4.4.1.patch /home/patches/pytorch.patch

ENV USE_NCCL 0
ENV USE_DISTRIBUTED 0
ENV USE_QNNPACK 0
ENV USE_PYTORCH_QNNPACK 0
ENV TORCH_CUDA_ARCH_LIST "5.3;6.2;7.2"
ENV PYTORCH_BUILD_VERSION 1.7.0
ENV PYTORCH_BUILD_NUMBER 1
ENV USE_OPENCV 1
ENV MAX_JOBS 4


RUN git clone --recursive --branch v1.7.0 https://github.com/pytorch/pytorch \
    && cd pytorch \
    && git apply /home/patches/pytorch.patch

ENV USE_OPENCV 0

RUN cd pytorch \
    && python3 setup.py bdist_wheel

RUN cd pytorch/dist \
    && pip install --no-cache-dir *.whl \
    && cd /home \
    && git clone --branch v0.8.2 https://github.com/pytorch/vision.git \
    && cd vision \
    && python3 setup.py bdist_wheel \
    && pip uninstall -y torch \
    && rm -rf /tmp/*

#===========================
FROM build_opencv AS build_nginx

WORKDIR /home/nginx-1.19.5

RUN  ./configure --with-compat \
     --prefix=/usr \
     --modules-path=/usr/lib/nginx/modules \
     --conf-path=/etc/nginx/nginx.conf \
     --error-log-path=/var/log/nginx/error.log \
     --http-log-path=/var/log/nginx/access.log \
     --pid-path=/var/run/nginx.pid \
    && make > /dev/null \
    && make install \
    && rm -rf nginx-1.19.5 \
    && mkdir /etc/nginx/conf.d \
    # remove default config
    && rm /etc/nginx/*.default \
    && rm /etc/nginx/nginx.conf \
    && useradd nginx

WORKDIR /home


#================================
FROM build_nginx AS build_yolo

COPY --from=build_torch /home/pytorch/dist/*.whl /home/torch_wheel/
COPY --from=build_torch /home/vision/dist/*.whl /home/vision_wheel/
RUN cd /home/torch_wheel \
    && pip3 install *.whl \
    && cd /home/vision_wheel \
    && pip3 install *.whl \
    && pip3 install --no-cache-dir tqdm Click \
    && rm -rf /home/torch_wheel \
    && rm -rf /home/vision_wheel \
    && rm -rf /home/pytorch \
    && rm -rf /home/vision \
    && rm -rf /home/build_opencv \
    && rm -rf /home/nginx-1.19.5 \
    && rm -rf /tmp/*



RUN git clone https://github.com/estasney/yolov5Jetson.git
ARG FRESH
RUN cd yolov5Jetson \
    && git pull \
    && pip3 install . \
    && cd /home \
    && rm -rf yolov5Jetson

#==================================
FROM build_yolo AS build_flask_yolo

RUN pip3 install --no-cache-dir flask uWSGI \
    && rm -rf /tmp/*

# Lowest number of processes to spawn
ENV UWSGI_CHEAPER 2
# Spawn up to these many processes as needed
ENV UWSGI_PROCESSES 8
# Max upload size. Is unlimited by default
ENV NGINX_MAX_UPLOAD 250m

# Copy the base uWSGI ini file to enable default dynamic uwsgi process number
COPY /ops/uwsgi/uwsgi.prod.ini /etc/uwsgi/uwsgi.ini
COPY /ops/supervisord/supervisord.prod.conf /etc/supervisor/conf.d/supervisord.conf
COPY /ops/nginx/http.prod.conf /etc/nginx/conf.d/http.conf

# Which uWSGI .ini file should be used, to make it customizable
ENV UWSGI_INI /app/flaskyolo/uwsgi.ini
ENV LISTEN_PORT 5000

COPY /ops/start/start.prod.sh /start.sh
COPY /ops/entrypoint/entrypoint.prod.sh /entrypoint.sh

RUN chmod +x /start.sh \
    && chmod +x /entrypoint.sh \
    && mkdir /app

COPY flaskyolo /app/flaskyolo

WORKDIR /app

COPY ops/prestart/prestart.prod.sh ./prestart.sh

RUN chmod 755 ./prestart.sh

ENV LANG=C.UTF-8
EXPOSE 5000


ENTRYPOINT ["/entrypoint.sh"]
CMD ["/start.sh"]
