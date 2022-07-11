FROM ubuntu:22.04
RUN apt update
# install neovim dependencies
RUN apt install -y git ninja-build gettext libtool libtool-bin autoconf \
                   automake cmake g++ pkg-config unzip curl doxygen
# install neovim
RUN git clone https://github.com/neovim/neovim
RUN cd neovim && make CMAKE_BUILD_TYPE=RelWithDebInfo && make install
# install required plugins
RUN mkdir plugins
RUN git clone https://github.com/MunifTanjim/nui.nvim plugins/nui.nvim
RUN git clone https://github.com/nvim-lua/plenary.nvim plugins/plenary.nvim
RUN git clone https://github.com/danilshvalov/neo-tree.nvim plugins/neo-tree.nvim
