#ifndef WEBVIEW_PLUGIN_H
#define WEBVIEW_PLUGIN_H

#include <functional>
#include <include/cef_base.h>
#include "webview_value.h"

namespace webview_cef {
    void initCEFProcesses(CefMainArgs args);
    void initCEFProcesses();
    void startCEF();
    void doMessageLoopWork();
    void sendKeyEvent(CefKeyEvent& ev);
    void HandleMethodCall(std::string name, WValue* values, std::function<void(int ,WValue*)> result);
    void SwapBufferFromBgraToRgba(void* _dest, const void* _src, int width, int height);
    void setPaintCallBack(std::function<void(const void*, int32_t , int32_t )> callback);
    void setInvokeMethodFunc(std::function<void(std::string, WValue*)> func);
    bool getPluginIsFocused();
}

#endif //WEBVIEW_PLUGIN_H