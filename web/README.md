# APK Converter - Web控制面板

将Google AI Studio生成的Web App转换为Android APK的在线服务。

## 项目结构

```
web/
├── frontend/          # Vue3 前端
│   ├── src/
│   │   ├── api/       # API调用
│   │   ├── App.vue    # 主组件
│   │   ├── main.js    # 入口文件
│   │   └── style.css  # 全局样式（赛博朋克风格）
│   ├── index.html
│   ├── package.json
│   └── vite.config.js
├── backend/           # FastAPI 后端
│   ├── main.py        # 主程序
│   ├── models.py      # Pydantic数据模型
│   └── requirements.txt
└── README.md
```

## 功能特性

- ✅ 上传ZIP文件（拖拽或点击）
- ✅ 配置APK参数（应用名、包名、版本等）
- ✅ 签名配置（可选）
- ✅ 创建构建任务
- ✅ 任务状态查询
- ✅ 任务列表管理
- ✅ 模拟构建完成（测试用）
- 🚧 实际APK构建功能（待实现）

## 快速开始

### 1. 启动后端

```bash
cd web/backend

# 安装依赖
pip install -r requirements.txt

# 启动服务
python main.py
```

后端将在 http://localhost:8000 运行

### 2. 启动前端

```bash
cd web/frontend

# 安装依赖
npm install

# 启动开发服务器
npm run dev
```

前端将在 http://localhost:3000 运行

## API 接口

| 方法 | 路径 | 描述 |
|------|------|------|
| GET | `/` | API信息 |
| POST | `/api/upload` | 上传ZIP文件 |
| POST | `/api/tasks` | 创建构建任务 |
| GET | `/api/tasks` | 获取任务列表 |
| GET | `/api/tasks/{id}` | 获取任务详情 |
| DELETE | `/api/tasks/{id}` | 删除任务 |
| POST | `/api/tasks/{id}/start` | 开始构建 |
| POST | `/api/tasks/{id}/simulate-complete` | 模拟完成（测试） |

## 配置说明

### AppConfig

| 字段 | 类型 | 必填 | 描述 |
|------|------|------|------|
| app_name | string | ✅ | 应用名称 |
| package_name | string | ✅ | 包名（如 com.example.app） |
| version_name | string | ❌ | 版本名称（默认 1.0.0） |
| version_code | int | ❌ | 版本号（默认 1） |
| output_format | string | ❌ | 输出格式：apk 或 aab |
| keystore_alias | string | ❌ | 签名密钥别名 |
| keystore_password | string | ❌ | 密钥库密码 |
| key_password | string | ❌ | 密钥密码 |

## 技术栈

- **前端**: Vue 3 + Vite + Axios
- **后端**: FastAPI + Pydantic + Uvicorn
- **样式**: 自定义CSS（赛博朋克深色主题）

## 注意事项

- Python 3.14 与 pydantic 存在部分兼容性问题，Swagger文档（/docs）可能无法正常显示
- 建议使用 Python 3.10-3.12 以获得完整功能支持

## 下一步开发计划

1. 集成Capacitor进行Web to Native转换
2. 使用Android SDK进行APK打包
3. 实现签名流程
4. 添加任务队列处理（Celery/Redis）
5. 文件存储优化（云存储）
6. 用户认证系统
