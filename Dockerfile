FROM docker.io/library/archlinux as update-mirrors
ARG PACMAN_PARALLELDOWNLOADS=5
RUN pacman-key --init \
    && pacman-key --populate archlinux \
    && sed 's/ParallelDownloads = \d+/ParallelDownloads = ${PACMAN_PARALLELDOWNLOADS}/g' -i /etc/pacman.conf \
    && sed 's/NoProgressBar/#NoProgressBar/g' -i /etc/pacman.conf

# update mirrorlist
#ADD https://raw.githubusercontent.com/greyltc/docker-archlinux/master/get-new-mirrors.sh /usr/bin/get-new-mirrors
#RUN chmod +x /usr/bin/get-new-mirrors
#RUN get-new-mirrors
RUN sed -i 's/^Server = https:\/\/.*/Server = https:\/\/archlinux.c3sl.ufpr.br\/$repo\/os\/$arch/' /etc/pacman.d/mirrorlist

RUN pacman -Syyu --noconfirm \
        aardvark-dns \
        apparmor \
        atuin \
        base-devel \
        bat \
        chromium \
        chezmoi \
        cifs-utils \
        curl \
        dust \
        elixir \
        exa \
        fd \
        ffmpeg \
        fish \
        fzf \
        fuse-overlayfs \
        gitlab-runner \
        git \
        git-lfs \
        go \
        helm \
        htop \
        imagemagick \
        links \
        lsof \
        jdk11-openjdk \
        jdk8-openjdk \
        jq \
        mariadb-clients \
        memcached \
        neovim \
        opencv \
        openssh \
        pgcli \
        php \
        podman \
        podman-compose \
        podman-docker \
        postgresql-libs \
        procs \
        redis \
        ripgrep \
        rust \
        starship \
        strace \
        sqlite3 \
        sudo \
        terraform \
        tmux \
        tmuxp \
        unzip \
        wget \
        wl-clipboard \
        xsel \
        xclip \
        yarn \
        zellij \
        zsh-autosuggestions \
        zsh-completions \
        zsh-history-substring-search \
        zsh-syntax-highlighting \
    ; pacman -Rns $(pacman -Qtdq) \
    ; pacman -Scc --noconfirm \
    ; rm -Rf /var/cache/pacman/pkg/*

RUN archlinux-java set java-8-openjdk

# optional directory to mount the host's home directory
RUN mkdir -p /mnt/host

# Install Yay and continue with it
FROM update-mirrors as build-helper-img
ARG AUR_USER=builduser
ARG HELPER=yay
ARG LUNARVIM_VERSION=1.3
ARG NEOVIM_VERSION=0.9

ADD helpers/add-aur.sh /root
RUN bash /root/add-aur.sh ${AUR_USER} ${HELPER}

# azure and google packages, each are more than 600 MB, uncompressed
# insomnia and postman, are also each larger than 300 MB
# dunno if they're worth having built-in. leaving just insomnia
RUN aur-install \
        asdf-vm \
        aws-cli \
        # azure-cli-bin \ 
        fselect-bin \
        # google-cloud-sdk \ heroku-cli-bin \
        insomnia-bin \
        kubectl-bin \
        kustomize-bin \
        openshift-client-bin \
        # postman-bin \
        skaffold-bin \
        terragrunt \
        tldr \
        urlview \
        wrk \
        zsh-git-prompt \
        zsh-theme-powerlevel10k \
        zsh-vi-mode \
    ; pacman -Rns $(pacman -Qtdq) \
    ; pacman -Scc --noconfirm \
    ; rm -Rf .cache/yay/* \
    ; rm -Rf /var/cache/foreign-pkg/*

RUN asdf plugin add crystal \
    && asdf plugin add dotnet-core \
    && asdf plugin add elixir \
    && asdf plugin add erlang \
    && asdf plugin add golang \
    && asdf plugin add haskell \
    && asdf plugin add java \
    && asdf plugin add julia \
    && asdf plugin add kotlin \
    && asdf plugin add lua \
    && asdf plugin add nim \
    && asdf plugin add nodejs \
    && asdf plugin add php \
    && asdf plugin add python \
    && asdf plugin add ruby \
    && asdf plugin add rust \
    && asdf plugin add scala \
    && asdf plugin add zig

RUN export PATH="$HOME/.asdf/shims:$PATH" && asdf install python latest && asdf install nodejs latest && asdf set -u python latest && asdf set -u nodejs latest

RUN export PATH="$HOME/.asdf/shims:$PATH" && LV_BRANCH="release-${LUNARVIM_VERSION}/neovim-${NEOVIM_VERSION}" \
    bash <(curl -s https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/install.sh) -y

# LunarVim ${LUNARVIM_VERSION} pins plugins for neovim ${NEOVIM_VERSION}, but Arch's `neovim`
# package (installed above) tracks upstream head, so two of LunarVim's bundled plugins are
# broken out of the box on this image:
#   1. nvim-treesitter (still) unconditionally registers its query predicates/directives
#      (has-ancestor?, has-parent?, trim!, ...); recent neovim already registers several of
#      these natively, so nvim-treesitter's own registration throws "Overriding existing
#      predicate/directive" and aborts loading treesitter entirely the first time a buffer
#      needing one of the colliding names is opened. Force every add_predicate/add_directive
#      call in the file to override instead of erroring (harmless for the ones that don't
#      collide with anything).
#   2. jose-elias-alvarez/null-ls.nvim was deleted upstream (the maintainer archived/removed
#      it); the community fork nvimtools/none-ls.nvim is a drop-in replacement that keeps the
#      same `require("null-ls")` module name, so LunarVim's own null-ls integration code needs
#      no other changes.
#   3. nvim-treesitter's exclude_children! directive calls node:range() without checking
#      that the captured node exists, which crashes the treesitter highlighter (as a
#      "Decoration provider" error) on some buffers/queries where that capture is optional.
#   4. bufferline.nvim asserts its internal segment table "must be a list", but it builds
#      that table as a literal `{ a, b, c, ... }` where some entries are legitimately nil
#      (e.g. no icon/duplicate-prefix for a given buffer); newer neovim's is_list check no
#      longer tolerates the resulting holes even though the actual summing code (which uses
#      pairs(), not ipairs()) handles them fine. The assert is purely defensive, so drop it.
RUN sed -i \
        -e 's/query\.add_predicate("has-ancestor?", has_ancestor)/query.add_predicate("has-ancestor?", has_ancestor, { force = true })/' \
        -e 's/query\.add_predicate("has-parent?", has_ancestor)/query.add_predicate("has-parent?", has_ancestor, { force = true })/' \
        -e 's/query\.add_directive("make-range!", function() end)/query.add_directive("make-range!", function() end, { force = true })/' \
        -e 's/^end)$/end, { force = true })/' \
        /root/.local/share/lunarvim/site/pack/lazy/opt/nvim-treesitter/lua/nvim-treesitter/query_predicates.lua \
    && sed -i -E ':a;N;$!ba;s/local node = match\[capture_id\]\n  local start_row, start_col, end_row, end_col = node:range\(\)/local node = match[capture_id]\n  if not node then\n    return\n  end\n  local start_row, start_col, end_row, end_col = node:range()/' \
        /root/.local/share/lunarvim/site/pack/lazy/opt/nvim-treesitter/lua/nvim-treesitter/query_predicates.lua \
    && sed -i \
        -e 's#{ "jose-elias-alvarez/null-ls.nvim", lazy = true },#{ "nvimtools/none-ls.nvim", name = "null-ls.nvim", lazy = true },#' \
        /root/.local/share/lunarvim/lvim/lua/lvim/plugins.lua \
    && sed -i \
        -e '/assert(utils\.is_list(segments), "Segments must be a list")/d' \
        /root/.local/share/lunarvim/site/pack/lazy/opt/bufferline.nvim/lua/bufferline/ui.lua

RUN mkdir -p /etc/skel/.local/share \
    && mkdir -p /etc/skel/.local/bin \
    && mkdir -p /etc/skel/.config/lvim \
    && mv /root/.local/share/lunarvim /etc/skel/.local/share/lunarvim \
    && mv /root/.local/bin/lvim /etc/skel/.local/bin/lvim \
    && mv /root/.asdf /etc/skel/ \
    && mv /root/.tool-versions /etc/skel/.tool-versions \
    && sed 's/\/root/$HOME/g' -i /etc/skel/.local/bin/lvim

COPY helpers/config.lua /etc/skel/.config/lvim
COPY helpers/webdevbox.zsh /etc/skel/.config/zsh/webdevbox.zsh
COPY helpers/initial_setup.zsh /etc/skel/.zshrc

USER root
RUN touch /var/tmp/first-time.lock

# configure podman for rootless
RUN groupadd --system podman \
    && useradd --system --shell /usr/bin/nologin --create-home --home-dir /home/podman podman -g podman \
    && echo podman:10000:65536 > /etc/subuid \
    && echo podman:10000:65536 > /etc/subgid

VOLUME /var/lib/containers
VOLUME /home/podman/.local/share/containers

ADD helpers/containers.conf /etc/containers/containers.conf
ADD helpers/podman-containers.conf /home/podman/.config/containers/containers.conf

RUN chown podman:podman -R /home/podman

# chmod containers.conf and adjust storage.conf to enable Fuse storage.
RUN chmod 644 /etc/containers/containers.conf \
    ; cp /usr/share/containers/storage.conf /etc/containers/storage.conf \
    ; sed -i -e 's|^#mount_program|mount_program|g' \
    -e 's|^# *additionalimagestores = \[\]|additionalimagestores = ["/var/lib/shared"]|g' \
    -e 's|^mountopt[[:space:]]*=.*$|mountopt = "nodev,fsync=0"|g' \
    -e 's|^#ignore_chown_errors = "false"|ignore_chown_errors = "true"|g' \
    /etc/containers/storage.conf

RUN mkdir -p /var/lib/shared/overlay-images \
    /var/lib/shared/overlay-layers \
    /var/lib/shared/vfs-images \
    /var/lib/shared/vfs-layers \
    ; touch /var/lib/shared/overlay-images/images.lock \
    ; touch /var/lib/shared/overlay-layers/layers.lock \
    ; touch /var/lib/shared/vfs-images/images.lock \
    ; touch /var/lib/shared/vfs-layers/layers.lock

ENV _CONTAINERS_USERNS_CONFIGURED=""

RUN echo 'export PATH="$HOME/.local/bin:$HOME/.asdf/shims:$PATH"' >> /etc/profile

CMD ["/bin/zsh"]
