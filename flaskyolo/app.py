from flask import Flask, request, jsonify, render_template
from yolov5.models.slim import SlimModelRunner
from PIL import Image, ImageDraw
import numpy as np
import base64
from io import BytesIO
import os

app = Flask(__name__)
model = SlimModelRunner(weights=os.path.join(app.root_path, "model/best.pt"), device='cuda')


def draw_predict(img, pred):
    img = Image.fromarray(img.astype(np.uint8))
    for detect in pred['detections']:
        box = detect['xyxy']
        cls = detect['cls']
        confidence = detect['confidence']

        print(cls, confidence)
        ImageDraw.Draw(img).rectangle(box, width=4, outline='red')  # plot

    with BytesIO() as output:
        img.save(output, format="JPEG")
        contents = output.getvalue()

    return contents


@app.route('/')
def hello_world():
    return render_template("upload.html")


@app.route('/api', methods=['POST'])
def api_predict():
    imgs = []

    for img_file in request.files.values():
        imgs.append(np.array(Image.open(img_file)))

    pred = model.detect(imgs)
    pred = [{'img_id': img_id, **p} for img_id, p in zip(request.files.keys(), pred)]

    return jsonify(pred), 200


@app.route('/imgdraw', methods=['POST'])
def imgdraw():
    f = request.files['file']
    img = [np.array(Image.open(f))]
    pred = model.detect(img)[0]

    img_data = draw_predict(img[0], pred)
    img_b64 = base64.b64encode(img_data)
    img_b64 = img_b64.decode('utf-8')

    return render_template("result.html", img=img_b64)


if __name__ == '__main__':
    app.run()
