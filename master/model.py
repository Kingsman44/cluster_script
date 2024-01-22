import pandas as pd
from keras.models import load_model
from sklearn.preprocessing import MinMaxScaler
import joblib

import warnings
warnings.filterwarnings("ignore")

def load_models():
    # Load models
    model_cpu = load_model("models/model_cpu.h5")
    model_memory = load_model("models/model_memory.h5")
    scaler_X_cpu = joblib.load("models/scaler_X_cpu.pkl")
    scaler_X_memory = joblib.load("models/scaler_X_memory.pkl")
    scaler_y_cpu = joblib.load("models/scaler_y_cpu.pkl")
    scaler_y_memory = joblib.load("models/scaler_y_memory.pkl")

    return model_cpu, model_memory, scaler_X_cpu, scaler_X_memory, scaler_y_cpu, scaler_y_memory

def load_values(cpu_file, memory_file, rtt_file):
    # Load CPU, Memory, and RTT values
    cpu_values = pd.read_csv(cpu_file, header=None, names=['cpu']).values.flatten()
    memory_values = pd.read_csv(memory_file, header=None, names=['memory']).values.flatten()
    rtt_values = pd.read_csv(rtt_file, header=None, names=['rtt']).values.flatten()

    return cpu_values, memory_values, rtt_values

def predict_next_values(model_cpu, model_memory, scaler_X_cpu, scaler_X_memory, scaler_y_cpu, scaler_y_memory, cpu_values, memory_values, rtt_values):
    sequence_length = 5

    # Prepare input data
    input_data_cpu = pd.DataFrame({
        'cpu': cpu_values,
        'rtt': rtt_values
    })
    input_data_memory = pd.DataFrame({
        'memory': memory_values,
        'rtt': rtt_values
    })

    # Reshape input data
    input_data_cpu_reshaped = input_data_cpu.values.reshape(1, sequence_length, 2)
    input_data_memory_reshaped = input_data_memory.values.reshape(1, sequence_length, 2)

    # Normalize input data
    input_data_cpu_normalized = scaler_X_cpu.transform(input_data_cpu_reshaped.reshape(-1, 2)).reshape(1, sequence_length, 2)
    input_data_memory_normalized = scaler_X_memory.transform(input_data_memory_reshaped.reshape(-1, 2)).reshape(1, sequence_length, 2)

    # Predict next values
    predicted_cpu_normalized = model_cpu.predict(input_data_cpu_normalized)
    predicted_memory_normalized = model_memory.predict(input_data_memory_normalized)

    # Inverse transform the predicted values
    predicted_cpu_original_scale = scaler_y_cpu.inverse_transform(predicted_cpu_normalized.reshape(1, -1))
    predicted_memory_original_scale = scaler_y_memory.inverse_transform(predicted_memory_normalized.reshape(1, -1))

    return predicted_cpu_original_scale[0, 0], predicted_memory_original_scale[0, 0]

def save_predictions(cpu_file, memory_file, pred_cpu, pred_memory):
    # Save predicted values to files
    pd.DataFrame({'predicted_cpu': [int(max(min(pred_cpu,100),0))]}).to_csv(cpu_file, header=None, index=None)
    pd.DataFrame({'predicted_memory': [int(max(min(pred_memory,100),0))]}).to_csv(memory_file, header=None, index=None)

def main():
    # File paths
    cpu_file = 'cluster/cpu_5.txt'
    memory_file = 'cluster/ram_5.txt'
    rtt_file = 'cluster/rtt_5.txt'
    pred_cpu_file = 'cluster/pred_cpu.txt'
    pred_memory_file = 'cluster/pred_ram.txt'

    # Load models
    model_cpu, model_memory, scaler_X_cpu, scaler_X_memory, scaler_y_cpu, scaler_y_memory = load_models()

    # Load values
    cpu_values, memory_values, rtt_values = load_values(cpu_file, memory_file, rtt_file)

    # Predict next values
    pred_cpu, pred_memory = predict_next_values(model_cpu, model_memory, scaler_X_cpu, scaler_X_memory, scaler_y_cpu, scaler_y_memory, cpu_values, memory_values, rtt_values)

    # Save predictions
    save_predictions(pred_cpu_file, pred_memory_file, pred_cpu, pred_memory)

if __name__ == "__main__":
    main()
