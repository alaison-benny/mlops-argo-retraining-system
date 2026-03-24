FROM python:3.9-slim

WORKDIR /app

# ആവശ്യമായ ലൈബ്രറികൾ ഇൻസ്റ്റാൾ ചെയ്യാൻ
RUN pip install mlflow pandas scikit-learn

# നമ്മുടെ ട്രെയിനിംഗ് സ്ക്രിപ്റ്റ് ഇതിലേക്ക് കോപ്പി ചെയ്യുക
COPY train.py .

# റൺ ചെയ്യാനുള്ള കമാൻഡ്
CMD ["python", "train.py"]
