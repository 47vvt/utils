
# script to make python graph simulations for VCE algo HESS
# irm x.gd/12alga | iex

Invoke-WebRequest -Uri https://bootstrap.pypa.io/get-pip.py -OutFile .\get-pip.py
python get-pip.py
pip install algorithmx
pip install networkx
pip install jupyter
code --install-extension ms-python.python
code --install-extension ms-toolsai.jupyter
