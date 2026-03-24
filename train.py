import mlflow
import mlflow.sklearn
from sklearn.ensemble import RandomForestRegressor
import pandas as pd

if __name__ == "__main__":
    mlflow.set_experiment("MLOps_Project")
    with mlflow.start_run():
        # ഒരു സിമ്പിൾ മോഡൽ ട്രെയിനിംഗ്
        df = pd.DataFrame({"a": [1, 2], "b": [3, 4]})
        model = RandomForestRegressor()
        model.fit(df, [0, 1])
        mlflow.log_param("model_type", "RandomForest")
        mlflow.sklearn.log_model(model, "model")
        print("Training Completed and Logged to MLflow!")
