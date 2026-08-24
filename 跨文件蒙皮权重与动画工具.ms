-- Cross-File Skin Weight Copy + Animation Restore
-- v3.3.1 - add keyframe-only capture mode (dropdown: keyframe/bake) for selected-bone animation
-- v3.3.0 - add world space option for selected-bone animation capture/apply (dropdown: local/world)
-- v3.2.6 - save/import/restore auto-fit animation range (save computes keyframe range of selected bones)
-- v3.2.5 - named multi-animation save; list + select to import
-- v3.2.4 - remove redundant "publish to another Max" button (save auto-publishes)
-- v3.2.3 - fix: sortTracksParentFirst used copy on struct array (returns OK) -> use collect; apply sorted parent-first order
-- v3.2.2 - streamline UI: copy/save publish automatically
-- v3.2.1 - fix: local Bone animation shared data parentheses
-- v3.2.0 - fix: save/apply selected Bone animation in parent-local space
-- v3.1.8 - fix: escape Windows path when serializing shared BIP
-- v3.1.7 - fix: shared animation outer array closing parenthesis
-- v3.1.6 - fix: shared track closing parentheses
-- v3.1.5 - fix: shared track frames/transforms array separator
-- v3.1.4 - fix: serialize cross-session animation as arrays, not struct constructors
-- v3.1.3 - fix: shared animation track serialization
-- v3.1.2 - animation sharing diagnostics and publish result validation
-- v3.1.1 - fix: biped figureMode check used non-existent getFigureMode
-- v3.1.0 - shared Biped and selected-bone animation transfer

try(destroyDialog SWT_Rollout)catch()

global SWT_CopiedWeights
global SWT_CopiedWeightsVer
global SWT_SharedWeights
global SWT_SharedWeightsVer
global SWT_SavedAnimation
global SWT_SharedAnimation
global SWTUtil
global SWT_CurrentSpace = "local"
global SWT_FrameMode = "keyframe"

struct SWTAnimTrack
(
    nodeName,
    frames = #(),
    positions = #(),
    rotations = #()
)

struct SWTAnimSnapshot
(
    startFrame,
    endFrame,
    bipedRootName,
    bipedFile,
    tracks = #(),
    space = "local"
)

struct SWTUtil
(
    fn getSkinModifier node =
    (
        if node == undefined do return undefined
        for mod in node.modifiers where classOf mod == Skin do return mod
        undefined
    ),

    fn getSharedWeightsPath =
    (
        (getDir #temp) + "\\SWT_SharedWeights.ms"
    ),

    fn getWorldVert node mesh vertIndex =
    (
        (getVert mesh vertIndex) * node.objectTransform
    ),

    fn getAnimationsDir =
    (
        local dir = (getDir #userScripts) + "\\SWT_Animations"
        if not doesFileExist dir do makeDir dir
        dir
    ),

    fn deleteSharedAnimation name =
    (
        local dir = SWTUtil.getAnimationsDir()
        local deleted = 0
        local msPath = dir + "\\" + name + ".ms"
        if doesFileExist msPath do ( deleteFile msPath; deleted += 1 )
        local bipPath = dir + "\\" + name + ".bip"
        if doesFileExist bipPath do ( deleteFile bipPath; deleted += 1 )
        deleted
    ),

    fn sanitizeAnimName name =
    (
        local badChars = #("\\","/",":","*","?","\"","<",">","|")
        for c in badChars do name = substituteString name c "_"
        name = trimLeft name
        name = trimRight name
        name
    ),

    fn listSharedAnimations =
    (
        local result = #()
        local dir = SWTUtil.getAnimationsDir()
        for f in (getFiles (dir + "\\*.ms")) do
            append result (getFilenameFile f)
        sort result
        result
    ),

    fn getSharedAnimationPath =
    (
        (getDir #temp) + "\\SWT_SharedAnimation.ms"
    ),

    fn getSharedBipPath =
    (
        (getDir #temp) + "\\SWT_SharedBiped.bip"
    ),

    fn getTempBipPath prefix =
    (
        (getDir #temp) + "\\" + prefix + "_" + (timestamp() as string) + ".bip"
    ),

    fn ensureBipedAnimMode root =
    (
        if root == undefined do return undefined
        local ctrl = root.controller
        if ctrl == undefined do return undefined
        try (if ctrl.figureMode do biped.setFigureMode ctrl false) catch()
        ctrl
    ),

    fn findBipedRoot =
    (
        for obj in objects do
        (
            try (if (classOf obj.controller as string) == "Vertical_Horizontal_Turn" do return obj) catch()
        )
        for obj in objects do
        (
            try (if (classOf obj.controller as string) == "BipSlave_Control" do return obj.controller.rootNode) catch()
        )
        undefined
    ),

    fn isBipedNode node =
    (
        try
        (
            local className = classOf node.controller as string
            className == "Vertical_Horizontal_Turn" or className == "BipSlave_Control"
        ) catch (false)
    ),

    fn getSelectedAnimNodes =
    (
        for obj in selection where not (SWTUtil.isBipedNode obj) collect obj
    ),

    fn captureTracks nodes space framemode =
    (
        local result = #()
        local startFrame = animationRange.start.frame as integer
        local endFrame = animationRange.end.frame as integer
        disableSceneRedraw()
        for node in nodes where isValidNode node do
        (
            local track = SWTAnimTrack nodeName:node.name
            if framemode == "keyframe" then
            (
                local keyFrames = #()
                for ctrl in #(node.pos.controller, node.rotation.controller) where ctrl != undefined do
                (
                    try (for k in ctrl.keys do append keyFrames (k.time.frame as integer)) catch()
                )
                sort keyFrames
                local uniqueFrames = #()
                for f in keyFrames do
                    if uniqueFrames.count == 0 or f != uniqueFrames[uniqueFrames.count] do append uniqueFrames f
                for frame in uniqueFrames where frame >= startFrame and frame <= endFrame do
                (
                    local t = frame as time
                    local worldTM = at time t node.transform
                    if space == "world" then
                    (
                        append track.frames frame
                        append track.positions worldTM.pos
                        append track.rotations (worldTM.rotation as quat)
                    )
                    else
                    (
                        local parentTM = if node.parent != undefined then (at time t node.parent.transform) else (matrix3 1)
                        local localTM = worldTM * (inverse parentTM)
                        append track.frames frame
                        append track.positions localTM.pos
                        append track.rotations (localTM.rotation as quat)
                    )
                )
            )
            else
            (
                for frame = startFrame to endFrame do
                (
                    local t = frame as time
                    local worldTM = at time t node.transform
                    if space == "world" then
                    (
                        append track.frames frame
                        append track.positions worldTM.pos
                        append track.rotations (worldTM.rotation as quat)
                    )
                    else
                    (
                        local parentTM = if node.parent != undefined then (at time t node.parent.transform) else (matrix3 1)
                        local localTM = worldTM * (inverse parentTM)
                        append track.frames frame
                        append track.positions localTM.pos
                        append track.rotations (localTM.rotation as quat)
                    )
                )
            )
            append result track
        )
        enableSceneRedraw()
        result
    ),

    fn sortTracksParentFirst tracks =
    (
        local pending = for t in tracks collect t
        local sorted = #()
        while pending.count > 0 do
        (
            local foundIndex = 0
            for i = 1 to pending.count while foundIndex == 0 do
            (
                local node = getNodeByName pending[i].nodeName exact:true
                if node == undefined or node.parent == undefined or (findItem (for t in pending collect t.nodeName) node.parent.name) == 0 do
                    foundIndex = i
            )
            if foundIndex == 0 then foundIndex = 1
            append sorted pending[foundIndex]
            deleteItem pending foundIndex
        )
        sorted
    ),

    fn applyTracks tracks space =
    (
        local applied = 0
        local sortedTracks = SWTUtil.sortTracksParentFirst tracks
        disableSceneRedraw()
        for track in sortedTracks do
        (
            local node = getNodeByName track.nodeName exact:true
            if node != undefined do
            (
                try
                (
                    try (deleteKeys node.pos.controller #allKeys) catch()
                    try (deleteKeys node.rotation.controller #allKeys) catch()
                    node.pos.controller = Bezier_Position()
                    node.rotation.controller = Euler_XYZ()
                    animate on for i = 1 to track.frames.count do
                        at time (track.frames[i] as time)
                        (
                            if space == "world" then
                                node.transform = track.rotations[i] as matrix3
                            else
                            (
                                local parentTM = if node.parent != undefined then (at time (track.frames[i] as time) node.parent.transform) else (matrix3 1)
                                local localTM = track.rotations[i] as matrix3
                                localTM.pos = track.positions[i]
                                node.transform = localTM * parentTM
                            )
                        )
                    applied += 1
                ) catch()
            )
        )
        enableSceneRedraw()
        applied
    ),

    fn getSelectedAnimRange =
    (
        local minFrame = undefined
        local maxFrame = undefined
        for obj in (SWTUtil.getSelectedAnimNodes()) where isValidNode obj do
        (
            local posCtrl = undefined
            local rotCtrl = undefined
            try ( posCtrl = obj.pos.controller ) catch()
            try ( rotCtrl = obj.rotation.controller ) catch()
            for ctrl in #(posCtrl, rotCtrl) do
            (
                if ctrl != undefined do
                (
                    try
                    (
                        for k in ctrl.keys do
                        (
                            local f = k.time.frame as integer
                            if minFrame == undefined or f < minFrame do minFrame = f
                            if maxFrame == undefined or f > maxFrame do maxFrame = f
                        )
                    ) catch()
                )
            )
        )
        if minFrame == undefined then undefined else #(minFrame, maxFrame)
    ),

    fn saveCurrentAnimation =
    (
        local root = SWTUtil.findBipedRoot()
        local snap = SWTAnimSnapshot()
        local animRange = SWTUtil.getSelectedAnimRange()
        if animRange != undefined then
            animationRange = interval (animRange[1] as time) (animRange[2] as time)
        snap.startFrame = animationRange.start.frame as integer
        snap.endFrame = animationRange.end.frame as integer
        snap.bipedRootName = if root != undefined then root.name else ""
        snap.space = SWT_CurrentSpace
        snap.tracks = SWTUtil.captureTracks (SWTUtil.getSelectedAnimNodes()) snap.space SWT_FrameMode
        if root != undefined do
        (
            SWTUtil.ensureBipedAnimMode root
            snap.bipedFile = SWTUtil.getTempBipPath "SWT_SavedBiped"
            try (biped.saveBipFile root.controller snap.bipedFile) catch (snap.bipedFile = "")
        )
        global SWT_SavedAnimation = snap
        snap
    ),

    fn applySnapshot snap =
    (
        if snap == undefined do return -1
        animationRange = interval (snap.startFrame as time) (snap.endFrame as time)
        local root = SWTUtil.findBipedRoot()
        if root != undefined and snap.bipedFile != undefined and snap.bipedFile != "" and doesFileExist snap.bipedFile do
        (
            SWTUtil.ensureBipedAnimMode root
            try (biped.loadBipFile root.controller snap.bipedFile #noRedraw) catch()
        )
        SWTUtil.applyTracks snap.tracks snap.space
    ),

    fn saveSharedAnimation name =
    (
        if SWT_SavedAnimation == undefined do return false
        local animDir = SWTUtil.getAnimationsDir()
        local animPath = animDir + "\\" + name + ".ms"
        local f = createFile animPath
        if f == undefined do return false
        local sourceBip = SWT_SavedAnimation.bipedFile
        local sharedBip = ""
        if sourceBip != undefined and sourceBip != "" and doesFileExist sourceBip do
        (
            sharedBip = animDir + "\\" + name + ".bip"
            if doesFileExist sharedBip do deleteFile sharedBip
            if not (copyFile sourceBip sharedBip) do return false
        )
        if SWT_SavedAnimation.bipedRootName != "" and sharedBip == "" do return false
        local serializedBip = substituteString sharedBip "\\" "\\\\"
        local serializedSpace = SWT_SavedAnimation.space
        if serializedSpace == undefined do serializedSpace = "local"
        format "global SWT_SharedAnimationData = #(% ,% ,\"%\",\"%\",\"%\",#(\n" SWT_SavedAnimation.startFrame SWT_SavedAnimation.endFrame SWT_SavedAnimation.bipedRootName serializedBip serializedSpace to:f
        for trackIndex = 1 to SWT_SavedAnimation.tracks.count do
        (
            local track = SWT_SavedAnimation.tracks[trackIndex]
            format "#(\"%\",#(" track.nodeName to:f
            for i = 1 to track.frames.count do
            (
                if i > 1 do format "," to:f
                format "%" track.frames[i] to:f
            )
            format "),#(" to:f
            for i = 1 to track.positions.count do
            (
                if i > 1 do format "," to:f
                format "%" track.positions[i] to:f
            )
            format "),#(" to:f
            for i = 1 to track.rotations.count do
            (
                if i > 1 do format "," to:f
                format "%" track.rotations[i] to:f
            )
            format "))" to:f
            if trackIndex < SWT_SavedAnimation.tracks.count do format ",\n" to:f
        )
        format "))\n" to:f
        close f
        true
    ),

    fn loadSharedAnimation name =
    (
        local path = SWTUtil.getAnimationsDir() + "\\" + name + ".ms"
        if not doesFileExist path do return #("missing", path)
        global SWT_SharedAnimation = undefined
        global SWT_SharedAnimationData = undefined
        try (fileIn path quiet:true) catch (return #("invalid", (getCurrentException() as string)))
        if SWT_SharedAnimationData == undefined or SWT_SharedAnimationData.count < 5 do return #("invalid", "共享动画数据为空")
        local data = SWT_SharedAnimationData
        local snapSpace = if data.count >= 6 and data[5] != undefined then data[5] as string else "local"
        local snap = SWTAnimSnapshot startFrame:data[1] endFrame:data[2] bipedRootName:data[3] bipedFile:data[4] space:snapSpace
        local trackArrayIndex = if data.count >= 6 then 6 else 5
        for rawTrack in data[trackArrayIndex] do
            append snap.tracks (SWTAnimTrack nodeName:rawTrack[1] frames:rawTrack[2] positions:rawTrack[3] rotations:rawTrack[4])
        global SWT_SharedAnimation = snap
        if snap.bipedRootName != "" and (not doesFileExist snap.bipedFile) do
            return #("missingBip", snap.bipedFile)
        local applied = SWTUtil.applySnapshot snap
        #("ok", applied)
    ),

    fn saveSharedWeights =
    (
        if SWT_CopiedWeights == undefined or SWT_CopiedWeights.count == 0 do return false
        local f = createFile (SWTUtil.getSharedWeightsPath())
        if f == undefined do return false

        format "global SWT_SharedWeightsVer = 3\n" to:f
        format "global SWT_SharedWeights = #(\n" to:f
        for entryIndex = 1 to SWT_CopiedWeights.count do
        (
            local entry = SWT_CopiedWeights[entryIndex]
            local boneNames = entry[1]
            local weights = entry[2]
            local pos = entry[3]
            format "#(#(" to:f
            for i = 1 to boneNames.count do
            (
                if i > 1 do format "," to:f
                format "\"%\"" boneNames[i] to:f
            )
            format "),#(" to:f
            for i = 1 to weights.count do
            (
                if i > 1 do format "," to:f
                format "%" (formattedPrint weights[i] format:".9f") to:f
            )
            format "),[%,%,%])" pos.x pos.y pos.z to:f
            if entryIndex < SWT_CopiedWeights.count do format ",\n" to:f
        )
        format "\n)\n" to:f
        close f
        true
    ),

    fn loadSharedWeights =
    (
        local path = SWTUtil.getSharedWeightsPath()
        if not doesFileExist path do return false
        global SWT_SharedWeights = undefined
        global SWT_SharedWeightsVer = undefined
        try(fileIn path quiet:true)catch(return false)
        if SWT_SharedWeights == undefined or SWT_SharedWeights.count == 0 do return false
        global SWT_CopiedWeights = SWT_SharedWeights
        global SWT_CopiedWeightsVer = SWT_SharedWeightsVer
        true
    ),

    fn copySelectedWeights node =
    (
        local skin = SWTUtil.getSkinModifier node
        if skin == undefined do return false

        select node
        max modify mode
        modPanel.setCurrentObject skin
        subObjectLevel = 1

        local selectedVerts = skinOps.GetSelectedVertices skin
        if selectedVerts.count == 0 do return false

        local mesh = snapshotAsMesh node
        local copied = #()
        for vertIndex in selectedVerts do
        (
            local boneNames = #()
            local weights = #()
            local count = skinOps.GetVertexWeightCount skin vertIndex
            for i = 1 to count do
            (
                local boneId = skinOps.GetVertexWeightBoneID skin vertIndex i
                local weight = skinOps.GetVertexWeight skin vertIndex i
                if weight > 0.0 do
                (
                    append boneNames (skinOps.GetBoneName skin boneId 0)
                    append weights weight
                )
            )
            append copied #(boneNames, weights, SWTUtil.getWorldVert node mesh vertIndex)
        )
        global SWT_CopiedWeights = copied
        global SWT_CopiedWeightsVer = 3
        SWTUtil.saveSharedWeights()
    ),

    fn getNearestEntry entries targetPosition =
    (
        local nearest = 1
        local nearestDistance = 1e30
        for i = 1 to entries.count do
        (
            local d = distance targetPosition entries[i][3]
            if d < nearestDistance do
            (
                nearest = i
                nearestDistance = d
            )
        )
        entries[nearest]
    ),

    fn pasteSelectedWeights node =
    (
        if SWT_CopiedWeights == undefined or SWT_CopiedWeights.count == 0 do return -1

        local skin = SWTUtil.getSkinModifier node
        if skin == undefined do return -2

        select node
        max modify mode
        modPanel.setCurrentObject skin
        subObjectLevel = 1

        local selectedVerts = skinOps.GetSelectedVertices skin
        if selectedVerts.count == 0 do return -3

        local targetBoneNames = #()
        local targetBoneIds = #()
        for boneId = 1 to skinOps.GetNumberBones skin do
        (
            append targetBoneNames (skinOps.GetBoneName skin boneId 0)
            append targetBoneIds boneId
        )

        local mesh = snapshotAsMesh node
        local pasted = 0
        for i = 1 to selectedVerts.count do
        (
            local entry = undefined
            if SWT_CopiedWeights.count == 1 then
                entry = SWT_CopiedWeights[1]
            else if SWT_CopiedWeights.count == selectedVerts.count then
                entry = SWT_CopiedWeights[i]
            else
                entry = SWTUtil.getNearestEntry SWT_CopiedWeights (SWTUtil.getWorldVert node mesh selectedVerts[i])

            local mappedBoneIds = #()
            local mappedWeights = #()
            for j = 1 to entry[1].count do
            (
                local found = findItem targetBoneNames entry[1][j]
                if found > 0 do
                (
                    append mappedBoneIds targetBoneIds[found]
                    append mappedWeights entry[2][j]
                )
            )
            if mappedBoneIds.count > 0 do
            (
                skinOps.ReplaceVertexWeights skin selectedVerts[i] mappedBoneIds mappedWeights
                pasted += 1
            )
        )
        pasted
    )
)

rollout SWT_Rollout "跨文件蒙皮权重复制" width:300 height:475
(
    label lblWeightInfo "权重：选择带 Skin 的模型顶点后复制；另一文件刷新、选择顶点后粘贴。" pos:[15,15] width:270 height:32
    button btnCopy "复制选中顶点权重" pos:[15,55] width:270 height:25
    button btnRefresh "刷新共享权重" pos:[15,85] width:130 height:25
    button btnPaste "粘贴到选中顶点" pos:[155,85] width:130 height:25

    groupBox grpAnimation "动画（不打开 .max 文件）" pos:[10,120] width:280 height:285
    label lblAnimInfo "保存 BIP + 选中骨骼动画，可命名保存多个。" pos:[20,138] width:260 height:20
    editText edtAnimName "动画名:" pos:[20,160] width:260 height:18
    dropdownList ddlAnimSpace "空间模式:" pos:[20,184] width:260 height:30 items:#("local", "world")
    dropdownList ddlAnimFrame "帧模式:" pos:[20,214] width:260 height:30 items:#("keyframe", "bake")
    button btnSaveAnimation "保存当前动画" pos:[20,250] width:270 height:25
    button btnRefreshAnimList "刷新动画列表" pos:[20,280] width:130 height:25
    button btnImportAnimation "导入选中动画" pos:[155,280] width:130 height:25
    listbox lbAnimList "已保存动画:" pos:[20,310] width:270 height:4
    button btnRestoreAnimation "恢复保存动画" pos:[20,378] width:130 height:25
    button btnDeleteAnimation "删除选中动画" pos:[155,378] width:130 height:25

    editText edtStatus "" pos:[15,418] width:270 height:20 readOnly:true
    button btnClose "关闭" pos:[105,448] width:90 height:20

    fn refreshAnimList =
    (
        lbAnimList.items = SWTUtil.listSharedAnimations()
    )

    on SWT_Rollout open do SWT_Rollout.refreshAnimList()

    on btnCopy pressed do
    (
        if selection.count == 0 then
            edtStatus.text = "请选择带 Skin 的模型和顶点。"
        else if SWTUtil.copySelectedWeights selection[1] then
            edtStatus.text = "已复制 " + SWT_CopiedWeights.count as string + " 个顶点权重。"
        else
            edtStatus.text = "复制失败：请在 Skin 顶点级别选择顶点。"
    )

    on btnRefresh pressed do
    (
        if SWTUtil.loadSharedWeights() then
            edtStatus.text = "已刷新 " + SWT_CopiedWeights.count as string + " 个顶点权重。"
        else
            edtStatus.text = "没有共享权重，请先在另一窗口复制。"
    )

    on btnPaste pressed do
    (
        if selection.count == 0 then
            edtStatus.text = "请选择带 Skin 的目标模型和顶点。"
        else
        (
            local result = SWTUtil.pasteSelectedWeights selection[1]
            if result > 0 then
                edtStatus.text = "已粘贴 " + result as string + " 个顶点权重。"
            else if result == -1 then
                edtStatus.text = "请先复制后刷新共享权重。"
            else if result == -2 then
                edtStatus.text = "目标模型没有 Skin 修改器。"
            else
                edtStatus.text = "粘贴失败：请在 Skin 顶点级别选择顶点。"
        )
    )

    on ddlAnimSpace selected arg do
    (
        SWT_CurrentSpace = ddlAnimSpace.items[arg]
        edtStatus.text = "空间模式：" + SWT_CurrentSpace
    )

    on ddlAnimFrame selected arg do
    (
        SWT_FrameMode = ddlAnimFrame.items[arg]
        edtStatus.text = "帧模式：" + SWT_FrameMode
    )

    on btnSaveAnimation pressed do
    (
        local animName = SWTUtil.sanitizeAnimName edtAnimName.text
        if animName == "" then
            edtStatus.text = "请输入动画名再保存。"
        else
        (
            local snap = SWTUtil.saveCurrentAnimation()
            if SWTUtil.saveSharedAnimation animName then
            (
                edtStatus.text = "已保存动画『" + animName + "』：BIP + " + snap.tracks.count as string + " 个选中骨骼。"
                SWT_Rollout.refreshAnimList()
            )
            else
                edtStatus.text = "保存失败：未检测到 Biped，或 BIP 写入失败。"
        )
    )

    on btnRefreshAnimList pressed do
    (
        SWT_Rollout.refreshAnimList()
        edtStatus.text = "已刷新列表，共 " + lbAnimList.items.count as string + " 个动画。"
    )

    on btnImportAnimation pressed do
    (
        if lbAnimList.selection == 0 then
            edtStatus.text = "请先在列表中选择要导入的动画。"
        else
        (
            local animName = lbAnimList.items[lbAnimList.selection]
            local result = SWTUtil.loadSharedAnimation animName
            if result[1] == "ok" then
            (
                SWT_CurrentSpace = SWT_SharedAnimation.space
                local idx = findItem ddlAnimSpace.items SWT_CurrentSpace
                if idx > 0 do ddlAnimSpace.selection = idx
                edtStatus.text = "已导入动画『" + animName + "』：BIP + " + result[2] as string + " 个选中骨骼动画。"
            )
            else if result[1] == "missing" then
                edtStatus.text = "找不到共享动画：" + result[2]
            else if result[1] == "missingBip" then
                edtStatus.text = "找到动画数据，但 BIP 缺失：" + result[2]
            else
                edtStatus.text = "共享动画无效：" + result[2]
        )
    )

    on btnRestoreAnimation pressed do
    (
        if SWT_SavedAnimation == undefined then
            edtStatus.text = "没有已保存动画。"
        else
        (
            local count = SWTUtil.applySnapshot SWT_SavedAnimation
            SWT_CurrentSpace = SWT_SavedAnimation.space
            local idx = findItem ddlAnimSpace.items SWT_CurrentSpace
            if idx > 0 do ddlAnimSpace.selection = idx
            edtStatus.text = "已恢复保存动画：" + count as string + " 个选中骨骼。"
        )
    )

    on btnDeleteAnimation pressed do
    (
        if lbAnimList.selection == 0 then
            edtStatus.text = "请先在列表中选择要删除的动画。"
        else
        (
            local animName = lbAnimList.items[lbAnimList.selection]
            if queryBox ("确定删除动画『" + animName + "』？此操作不可恢复。") title:"删除动画" then
            (
                local n = SWTUtil.deleteSharedAnimation animName
                SWT_Rollout.refreshAnimList()
                edtStatus.text = "已删除动画『" + animName + "』（" + n as string + " 个文件）。"
            )
            else
                edtStatus.text = "已取消删除。"
        )
    )

    on btnClose pressed do destroyDialog SWT_Rollout
)

createDialog SWT_Rollout style:#(#style_titlebar, #style_sysmenu, #style_toolwindow)
