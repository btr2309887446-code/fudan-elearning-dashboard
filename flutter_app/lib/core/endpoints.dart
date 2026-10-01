/// 所有用到的服务地址，集中一处便于核对与替换。

library;

/// eLearning（Canvas LMS）。
const String canvasBase = 'https://elearning.fudan.edu.cn';
const String canvasHost = 'elearning.fudan.edu.cn';

/// 复旦大学统一身份认证。
const String idBase = 'https://id.fudan.edu.cn';
const String idHost = 'id.fudan.edu.cn';

/// CAS 入口：从这里开始整条登录链。
const String loginEntry = '$canvasBase/login/cas';
