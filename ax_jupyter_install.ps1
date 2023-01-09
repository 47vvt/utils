Invoke-WebRequest -Uri https://bootstrap.pypa.io/get-pip.py -OutFile .\get-pip.py
python get-pip.py
pip install nodejs
pip install npm
pip install algorithmx
pip install jupyterlab

jupyter labextension install @jupyter-widgets/jupyterlab-manager --no-build
jupyter lab build

code --install-extension ms-python.python
code --install-extension ms-toolsai.jupyter
