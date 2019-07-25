# How To Set up an Auto Scaling Elixir Cluster
This project is designed to show you how to create an auto-scaling elixir cluster using Elixir 1.9 and Kubernetes. Each branch of the project is designed to follow the [slide deck](https://docs.google.com/presentation/d/1xN2Mi_Q-TfwGHNnJ3OczKTvhq_bFyOcMNBa1H4NPMak/edit?usp=sharing) of the associated presentation.

The branches are ordered from 01-22 so that you can easily see what is changed at each step. If a branch is missing it's because that slide contained only commands, not code changes. This README also covers a summary of what is done top to bottom.

## Part 1 - Creating the App
### New the project
From the working directory on your local development machine
```
$ mix phx.new el_kube
```
### Open the project
I am using [vscode](https://code.visualstudio.com/)
```
$ cd el_kube && code .
```

### Edit mix.exs
#### update project key to 1.9
`elixir: "~> 1.9",`

#### add extra_applications
```
  def application do
    [
      mod: {YourProject.Application, []},
      extra_applications: [:logger, :runtime_tools, :peerage]
    ]
  end
```

#### add dependencies
Add [peerage](https://github.com/mrluc/peerage)
```
  defp deps do
    [
      {:phoenix, "~> 1.4.6"},
      {:phoenix_pubsub, "~> 1.1"},
      {:phoenix_ecto, "~> 4.0"},
      {:ecto_sql, "~> 3.0"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 2.11"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:gettext, "~> 0.11"},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"},
      {:peerage, "~> 1.0"}
    ]
  end
```
Don't forget to `$ mix deps.get` if necessary

### Initialize the release
```
$ mix release.init
```

#### Update rel/env.sh.eex
Uncomment RELEASE_DISTRIBUTION and RELEASE_NODE and change the localhost IP to an environment variable

```
export RELEASE_DISTRIBUTION=name
export RELEASE_NODE=<%= @release.name %>@${HOSTNAME}
```

#### Delete config/prod.secret.exs
This file won't be used

$ rm config/prod.secret.exs

#### Create config/releases.exs
$ touch config/releases.exs

#### Edit config/releases.exs
```
import Config

service_name = System.fetch_env!("SERVICE_NAME")
db_url = System.fetch_env!("DB_URL")
secret_key_base = System.fetch_env!("SECRET_KEY_BASE")
port = System.fetch_env!("PORT")

config :el_kube, YourProject.Repo, url: db_url

config :el_kube, YourProjectWeb.Endpoint,
  http: [port: port],
  secret_key_base: secret_key_base,
  url: [host: {:system, "APP_HOST"}, port: {:system, "PORT"}]

config :peerage, via: Peerage.Via.Dns,
  dns_name: service_name,
  app_name: "el_kube"

```

#### Edit config/prod.exs
#### Configure Phoenix
1. Remove the url key from the endpoint config
2. Add endpoint config key/value `server: true`
#### Drop the import to prod.secret.exs
3. Remove the import_config "prod.secret.exs" at the bottom of config/prod.exs


### Edit config/config.exs
#### Add your ecto database settings
This demonstrates how you can put base values in the config and layer on top with the environment specific configs
```
config :el_kube, YourProject.Repo,
  adapter: Ecto.Adapters.Postgres,
  pool_size: 10
```

### Edit config/dev.exs
#### Configure Peerage
So that it will run quietly in development
```
config :peerage,
  via: Peerage.Via.List,
  node_list: [:"el_kube@127.0.0.1"],
  log_results: false
```

### Compile
#### Generate the digest
```
$ mix phx.digest
```

#### Generate the release
```
$ MIX_ENV=prod mix release
```

### Create a test database
```
$ mix ecto.create
```

### Test Run
#### Run the release
Console 1:
```
DB_URL=ecto://postgres:postgres@localhost/el_kube_dev RELEASE_COOKIE=foo SECRET_KEY_BASE=foo HOSTNAME=127.0.0.1 SERVICE_NAME=localhost.svc APP_HOST=localhost PORT=4000 _build/prod/rel/el_kube/bin/el_kube start
```

You should now be able to open http://localhost:4000

#### Test Ecto connectivity
The `:ok` tuple indicates success.

From Console 2:
```
DB_URL=ecto://postgres:postgres@localhost/el_kube_dev RELEASE_COOKIE=foo SECRET_KEY_BASE=foo HOSTNAME=127.0.0.1 PORT=4000 MIX_ENV=prod SERVICE_NAME=localhost.svc APP_HOST=localhost _build/prod/rel/el_kube/bin/el_kube remote

Interactive Elixir (1.8.1) - press Ctrl+C to exit (type h() ENTER for help)
iex(el_kube@127.0.0.1)1> Ecto.Adapters.SQL.query(YourProject.Repo, "Select 1 as testing")
17:34:23.041 [debug] QUERY OK db=0.3ms queue=0.6ms
Select 1 as testing []
{:ok,
 %Postgrex.Result{
   columns: ["testing"],
   command: :select,
   connection_id: 20104,
   messages: [],
   num_rows: 1,
   rows: [[1]]
 }}
iex(el_kube@127.0.0.1)2>
```

## Part 2 - Dockerizing the App
### Create the Dockerfile and .dockerignore
#### Dockerfile
```
FROM elixir:1.9.0-alpine AS builder

ENV MIX_ENV=prod

WORKDIR /usr/local/el_kube

# This step installs all the build tools we'll need
RUN apk update \
    && apk upgrade --no-cache \
    && apk add --no-cache \
      nodejs-npm \
      alpine-sdk \
      openssl-dev \
    && mix local.rebar --force \
    && mix local.hex --force

# Copies our app source code into the build container
COPY . .

# Compile Elixir
RUN mix do deps.get, deps.compile, compile

# Compile Javascript
RUN cd assets \
    && npm install \
    && ./node_modules/webpack/bin/webpack.js --mode production \
    && cd .. \
    && mix phx.digest

# Build Release
RUN mkdir -p /opt/release \
    && mix release \
    && mv _build/${MIX_ENV}/rel/el_kube /opt/release

# Create the runtime container
FROM erlang:22-alpine as runtime

# Install runtime dependencies
RUN apk update \
    && apk upgrade --no-cache \
    && apk add --no-cache gcc

WORKDIR /usr/local/el_kube

COPY --from=builder /opt/release/el_kube .

CMD [ "bin/el_kube", "start" ]

HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=2 \
 CMD nc -vz -w 2 localhost 4000 || exit 1
```

#### .dockerignore
```
_build/
.elixir_ls/
.git/
.vscode/
deps/
priv/static/
k8s/
test/
.dockerignore
.env
.formatter.exs
.gitignore
.travis.yml
Dockerfile
README.md
```

### Build the container
```
$ docker build -t el_kube:latest .
```

### Testing the container in docker
#### Start the container
```
$ docker network create el-kube-net
$ docker run --rm -d -h db -e POSTGRES_DB=el_kube_prod -p 5432 --name db --network el-kube-net postgres:9.6
$ docker run -it --rm -e DB_URL=ecto://postgres:postgres@db/el_kube_prod -e RELEASE_COOKIE=secret-cookie -e SERVICE_NAME=el-kube -e SECRET_KEY_BASE=foo -e PORT=4000 -e APP_HOST=localhost -p 4000 --network el-kube-net --publish 4000:4000 el_kube:latest
```
<!--
### Run the container
```
# docker-compose.yaml
version: '3.5'

services:
  myapp:
    image: myapp:latest
    container_name: myapp
    env_file: docker.env
    depends_on:
      - db
    ports:
      - "4000:4000"

  db:
    image: postgres:9.6
    container_name: db
    environment:
      POSTGRES_DB: myapp_dev
```
$ docker-compose up
-->

#### Test the container
```
$ curl http://localhost:4000
# you should get back some html and a 200
```
## Part 3 - Deploying to k8s
### Create your k8s config files
The filename is in the comment at the top of the yaml file.
#### Create a directory for your k8s config
```
$ mkdir k8s
```
#### Create a Persistent Volume Claim
```
# k8s/pvc.yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: postgres-pvc
  labels:
    app: postgres
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

#### Create the db using the PVC
```
# k8s/db.yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: db
spec:
  replicas: 1
  strategy:
    type: Recreate
  template:
    metadata:
      creationTimestamp: null
      labels:
        app: postgresql
    spec:
      containers:
      - env:
        - name: POSTGRES_DB
          value: el_kube_prod
        image: postgres:9.6
        name: db
        ports:
        - containerPort: 5432
        resources: {}
        volumeMounts:
        - mountPath: /var/lib/postgresql/data
          name: data
      hostname: db
      restartPolicy: Always
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: postgres-pvc
```

#### Create the db service
```
# k8s/db-svc.yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app: postgresql
  name: db
spec:
  ports:
  - name: postgres
    port: 5432
    targetPort: 5432
  selector:
    app: postgresql
```

#### Create the el_kube service
```
# k8s/el-kube-svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: el-kube
spec:
  clusterIP: None
  selector:
    app: el-kube
  ports:
  - name: http
    port: 4000
  - name: epmd
    port: 4369
```

#### Build the container on minikube
```
$ eval $(minikube docker-env)
$ docker build -t el_kube:latest .
```

#### Create the el_kube deployment
```
# k8s/el-kube.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: el-kube-deployment
  labels:
    app: el-kube
spec:
  replicas: 3
  selector:
    matchLabels:
      app: el-kube
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 34%
      maxUnavailable: 34%
  template:
    metadata:
      name: el-kube
      labels:
        app: el-kube
    spec:
      containers:
      - name: el-kube
        image: el_kube:latest
        imagePullPolicy: Never
        env:
          - name: APP_HOST
            value: el-kube.com
          - name: DB_URL
            value: ecto://postgres:postgres@db/el_kube_prod
          - name: HOSTNAME
            valueFrom:
              fieldRef:
                fieldPath: status.podIP
          - name: PORT
            value: "4000"
          - name: RELEASE_COOKIE
            value: el-kube-secret-cookie
          - name: SECRET_KEY_BASE
            value: super-secret-key-base
          - name: SERVICE_NAME
            value: el-kube.default.svc.cluster.local
        resources: {}
        securityContext:
          privileged: false
          procMount: Default
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
      dnsPolicy: ClusterFirst
      restartPolicy: Always
      schedulerName: default-scheduler
      securityContext: {}
      terminationGracePeriodSeconds: 30
```

### Check your work
```
$ kubectl exec -it el-kube-deployment-<hash> sh
/usr/local/el_kube # bin/el_kube remote
Erlang/OTP 22 [erts-10.4.4] [source] [64-bit] [smp:2:2] [ds:2:2:10] [async-threads:1] [hipe]

Interactive Elixir (1.9.0) - press Ctrl+C to exit (type h() ENTER for help)
iex(el_kube@172.17.0.9)1> Node.list
[:"el_kube@172.17.0.7", :"el_kube@172.17.0.8"]
iex(el_kube@172.17.0.9)2> ElKube.Repo.query("select 1 as testing")
{:ok,
 %Postgrex.Result{
   columns: ["testing"],
   command: :select
...
```

### Grow your cluster
```
$ # update the number of replicas to 5 in k8s/el-kube.yaml
$ kubectl apply -f k8s/el-kube.yaml
deployment.apps/el-kube-deployment configured
$ k exec -it el-kube-deployment-zzzzz sh
iex(el_kube@172.17.0.9)1> Node.list
[:"el_kube@172.17.0.7", :"el_kube@172.17.0.8", :"el_kube@172.17.0.11", :"el_kube@172.17.0.10"]
```