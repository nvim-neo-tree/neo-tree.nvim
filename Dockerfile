# --- Builder Stage ---
FROM alpine:latest AS builder

RUN apk update && apk add --no-cache \
    build-base \
    ninja-build \
    cmake \
    coreutils \
    curl \
    gettext-tiny-dev \
    git

# Install neovim
RUN git clone --depth=1 https://github.com/neovim/neovim --branch release-0.10
RUN cd neovim && make CMAKE_BUILD_TYPE=RelWithDebInfo && make install

# --- Final Stage ---
FROM alpine:latest

RUN apk update && apk add --no-cache \
    libstdc++ # Often needed for C++ applications

COPY --from=builder /usr/local/bin/nvim /usr/local/bin/nvim
COPY --from=builder /usr/local/share /usr/local/share

ARG PLUG_DIR="/root/.local/share/nvim/site/pack/neo-tree/start"
RUN mkdir -p $PLUG_DIR

RUN apk add --no-cache git # Git is needed to clone plugins in the final image

COPY .dependencies $PLUG_DIR
COPY . $PLUG_DIR/neo-tree.nvim

WORKDIR $PLUG_DIR/neo-tree.nvim
